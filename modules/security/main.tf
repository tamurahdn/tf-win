##############################
# KMS (共通暗号化キー)
##############################
# EBS/S3/FSx/Secrets Manager/CloudWatch Logsで共用するCMK。
# サービスごとに分離したい場合は本モジュールを複製して利用する。

resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} 用共通暗号化キー (EBS/S3/FSx/Secrets Manager/Logs)"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-kms"
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-key"
  target_key_id = aws_kms_key.this.key_id
}

##############################
# Security Group: Windows EC2
##############################

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Windows EC2用セキュリティグループ。既定ではSession Manager経由の管理を前提としインバウンドを開放しない。"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic (required for SSM/S3/FSx communication)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rdp_cidr" {
  for_each          = var.enable_rdp_access ? toset(var.rdp_allowed_cidrs) : toset([])
  security_group_id = aws_security_group.ec2.id
  description       = "Allow RDP access from specified CIDR (enabled only when required)"
  cidr_ipv4         = each.value
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rdp_from_bastion" {
  count                        = var.enable_bastion ? 1 : 0
  security_group_id            = aws_security_group.ec2.id
  description                  = "Allow RDP access from bastion security group"
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 3389
  to_port                      = 3389
  ip_protocol                  = "tcp"
}

##############################
# Security Group: Bastion (踏み台、オプション)
##############################

resource "aws_security_group" "bastion" {
  count       = var.enable_bastion ? 1 : 0
  name        = "${var.name_prefix}-bastion-sg"
  description = "踏み台ホスト用セキュリティグループ"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_rdp" {
  for_each          = var.enable_bastion ? toset(var.rdp_allowed_cidrs) : toset([])
  security_group_id = aws_security_group.bastion[0].id
  description       = "Allow RDP access to bastion from specified CIDR"
  cidr_ipv4         = each.value
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"
}

##############################
# Security Group: FSx for Windows File Server
##############################

resource "aws_security_group" "fsx" {
  name        = "${var.name_prefix}-fsx-sg"
  description = "FSx for Windows File Server用セキュリティグループ(SMB/AD関連ポートをVPC内からのみ許可)"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow SMB (445) access from within VPC"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow RPC/NetBIOS/LDAP ports (135, 137-139, 389, 636, 3268-3269) from within VPC"
    from_port   = 135
    to_port     = 139
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow LDAP/GC related ports from within VPC"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-fsx-sg"
  })
}

##############################
# Secrets Manager
##############################
# アプリケーション実行に必要な認証情報(DB接続情報、ライセンスキー等)を格納する。
# シークレットの値自体はTerraform管理外とし、初期値はプレースホルダーとする。
# 実際の値は運用担当者が`aws secretsmanager put-secret-value`等で別途設定すること
# (機微情報をTerraformコード・tfstateへ平文で残さないための設計判断)。

resource "aws_secretsmanager_secret" "app" {
  count                   = var.create_app_secret ? 1 : 0
  name                    = "${var.name_prefix}-app-secret"
  description             = "アプリケーション実行に必要な認証情報。値はplaceholderで作成し、運用担当者が別途設定する。"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-secret"
  })
}

resource "aws_secretsmanager_secret_version" "app" {
  count         = var.create_app_secret ? 1 : 0
  secret_id     = aws_secretsmanager_secret.app[0].id
  secret_string = jsonencode({ placeholder = "REPLACE_ME" })

  lifecycle {
    ignore_changes = [secret_string] # 運用側での値更新をTerraformが上書きしないようにする
  }
}
