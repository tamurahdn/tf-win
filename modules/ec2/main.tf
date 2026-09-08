# Windows Server 2022 最新のAWS公式AMIを動的に取得する。
# ハードコードを避けるためSSM Public Parameterを利用する。
data "aws_ssm_parameter" "windows_2022_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-Japanese-Full-Base"
}

locals {
  ami_id = data.aws_ssm_parameter.windows_2022_ami.value

  # UserDataでセットアップスクリプト実行モードに応じた処理を切り替える。
  # - userdata:       S3からスクリプトを取得し即時実行する
  # - ssm_run_command / state_manager: CloudWatch Agentのセットアップのみ行い、
  #   アプリ用セットアップスクリプトはSSM経由で別途実行する
  user_data = templatefile("${path.module}/templates/userdata.ps1.tpl", {
    execution_mode                         = var.setup_script_execution_mode
    scripts_bucket_name                    = var.scripts_bucket_name
    setup_script_s3_key                    = var.setup_script_s3_key
    cloudwatch_agent_config_ssm_param_name = var.cloudwatch_agent_config_ssm_param_name
    fsx_dns_name                           = var.fsx_dns_name
  })
}

resource "aws_instance" "this" {
  count                       = var.instance_count
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = false
  user_data                   = local.user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2必須化
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    encrypted             = true
    kms_key_id            = var.kms_key_id
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.name_prefix}-ec2-${count.index}-root"
    })
  }

  monitoring = true # 詳細監視を有効化(1分間隔メトリクス)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-${count.index}"
  })

  lifecycle {
    ignore_changes = [ami] # AMI更新による意図しない再作成を防止(更新時はvar経由で明示的に変更)
  }
}
