# 初期セットアップスクリプトの実行方式を切り替え可能にするモジュール。
#
# - userdata:       ec2モジュール側のUserDataでS3からスクリプトを取得し実行する(本モジュールでは何もしない)
# - ssm_run_command: SSMドキュメントを作成するのみとし、実行はCLI/コンソール/CI等から
#                    aws ssm send-command で明示的にキックする運用とする
# - state_manager:   SSMアソシエーション(State Manager)により、対象インスタンスへ
#                    定期的/起動時に自動適用する

resource "aws_ssm_document" "run_setup_script" {
  count           = var.setup_script_execution_mode != "userdata" ? 1 : 0
  name            = "${var.name_prefix}-run-setup-script"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "S3に配置された初期セットアップスクリプト(PowerShell)をダウンロードして実行する"
    parameters = {
      s3Bucket = {
        type        = "String"
        description = "スクリプトが格納されたS3バケット名"
        default      = var.scripts_bucket_name
      }
      s3Key = {
        type        = "String"
        description = "スクリプトのS3キー"
        default      = var.setup_script_s3_key
      }
    }
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "runSetupScript"
        inputs = {
          timeoutSeconds = 3600
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "$localPath = Join-Path $env:TEMP (Split-Path -Leaf '{{ s3Key }}')",
            "Read-S3Object -BucketName '{{ s3Bucket }}' -Key '{{ s3Key }}' -File $localPath",
            "Write-Host \"Executing $localPath\"",
            "& $localPath"
          ]
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-run-setup-script"
  })
}

##############################
# State Manager Association
##############################
# setup_script_execution_mode = "state_manager" の場合のみ作成。
# 起動時(association時)に1回実行する設定とし、恒久的な定期実行が必要な場合は
# schedule_expressionを追加すること。

resource "aws_ssm_association" "run_setup_script" {
  count = var.setup_script_execution_mode == "state_manager" && length(var.instance_ids) > 0 ? 1 : 0

  name = aws_ssm_document.run_setup_script[0].name

  targets {
    key    = "InstanceIds"
    values = var.instance_ids
  }

  parameters = {
    s3Bucket = var.scripts_bucket_name
    s3Key    = var.setup_script_s3_key
  }

  apply_only_at_cron_interval = false

  output_location {
    s3_bucket_name = var.output_s3_bucket_name
    s3_key_prefix  = "ssm-association-logs/${var.name_prefix}"
  }
}
