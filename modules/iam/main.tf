# Windows EC2用IAMロール
# 最小権限の原則に基づき、SSM管理・CloudWatch監視・S3/FSx/Secrets Manager/KMSへの
# 必要最小限のアクセスのみを許可する。

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-role"
  })
}

##############################
# AWS管理ポリシーのアタッチ
##############################

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

##############################
# S3アクセス(最小権限: 対象バケットのみ)
##############################

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid     = "S3ListBuckets"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = var.s3_bucket_arns
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [for arn in var.s3_bucket_arns : "${arn}/*"]
  }
}

resource "aws_iam_policy" "s3_access" {
  name   = "${var.name_prefix}-s3-access"
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.s3_access.arn
}

##############################
# FSxアクセス(DescribeとMount関連の最小権限)
##############################

data "aws_iam_policy_document" "fsx_access" {
  statement {
    sid    = "FSxDescribe"
    effect = "Allow"
    actions = [
      "fsx:DescribeFileSystems",
      "fsx:DescribeBackups",
    ]
    resources = [var.fsx_arn]
  }
}

resource "aws_iam_policy" "fsx_access" {
  name   = "${var.name_prefix}-fsx-access"
  policy = data.aws_iam_policy_document.fsx_access.json
}

resource "aws_iam_role_policy_attachment" "fsx_access" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.fsx_access.arn
}

##############################
# CloudWatch Logs書き込み(対象ロググループのみ)
##############################

data "aws_iam_policy_document" "logs_access" {
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = length(var.log_group_arns) > 0 ? [for arn in var.log_group_arns : "${arn}:*"] : ["*"]
  }
}

resource "aws_iam_policy" "logs_access" {
  name   = "${var.name_prefix}-logs-access"
  policy = data.aws_iam_policy_document.logs_access.json
}

resource "aws_iam_role_policy_attachment" "logs_access" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.logs_access.arn
}

##############################
# KMS利用(暗号化されたS3/EBS/Secrets Managerの復号に必要)
##############################

data "aws_iam_policy_document" "kms_access" {
  statement {
    sid    = "KMSUsage"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_policy" "kms_access" {
  name   = "${var.name_prefix}-kms-access"
  policy = data.aws_iam_policy_document.kms_access.json
}

resource "aws_iam_role_policy_attachment" "kms_access" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.kms_access.arn
}

##############################
# Secrets Managerアクセス(必要時のみ、対象シークレットのみ)
##############################

data "aws_iam_policy_document" "secrets_access" {
  count = length(var.secret_arns) > 0 ? 1 : 0

  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arns
  }
}

resource "aws_iam_policy" "secrets_access" {
  count  = length(var.secret_arns) > 0 ? 1 : 0
  name   = "${var.name_prefix}-secrets-access"
  policy = data.aws_iam_policy_document.secrets_access[0].json
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  count      = length(var.secret_arns) > 0 ? 1 : 0
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.secrets_access[0].arn
}

##############################
# Instance Profile
##############################

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-instance-profile"
  })
}
