# Windows EC2から収集する各種ログのロググループを一元管理する。
# 実際のログ転送設定(CloudWatch Agent設定ファイル)はssmモジュール/セットアップスクリプト側で
# 本モジュールが払い出すロググループ名を参照して構成する。

locals {
  log_groups = {
    system_event    = "system-event-log"      # Windows Event Log (System)
    application     = "application-event-log" # Windows Event Log (Application)
    security_event  = "security-event-log"    # Windows Event Log (Security)
    powershell      = "powershell-log"        # PowerShellスクリプト実行ログ
    ssm             = "ssm-agent-log"         # SSM Agent / Run Command 実行ログ
    setup           = "setup-log"             # 初期セットアップスクリプト実行ログ
    application_log = "application-log"       # 対象アプリケーションのログ格納先(格納のみ、内容はアプリ依存)
    job_execution   = "job-execution-log"     # Launcherが出力するジョブ実行ログ(構造化ログ)
    step_functions  = "step-functions-log"    # Step Functionsステートマシン実行ログ(use_step_functions=true時のみ利用)
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = local.log_groups
  name              = "/${var.name_prefix}/${each.value}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.value}"
  })
}
