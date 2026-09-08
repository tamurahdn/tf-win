# Lambda(Job Dispatcher)/SSM/ジョブ実行に関する監視
# EC2・FSx関連の既存アラームは modules/monitoring に定義済みのため、
# 本モジュールはイベント駆動ジョブ実行基盤に固有の監視対象のみを追加する。

locals {
  alarm_actions = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
}

# --- Lambda Errors ---
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-job-dispatcher-errors"
  alarm_description   = "Job Dispatcher Lambdaがエラーを返した場合に検知する"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

# --- Lambda Throttles ---
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name_prefix}-lambda-job-dispatcher-throttles"
  alarm_description   = "Job Dispatcher Lambdaがスロットリングされた場合に検知する"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

# --- Lambda Duration(タイムアウト近接を検知するプロキシ指標) ---
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.name_prefix}-lambda-job-dispatcher-duration-near-timeout"
  alarm_description   = "Job Dispatcher Lambdaの実行時間がタイムアウト値の80%を超えた場合に検知する"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.lambda_timeout_seconds * 1000 * 0.8
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

# --- SSM Run Command失敗検知 ---
# Launcher/SSMエージェントが構造化ログへ "ssm_command_failed" 等を出力する前提で、
# メトリクスフィルタによりログベースのカウンタメトリクスへ変換して監視する。
resource "aws_cloudwatch_log_metric_filter" "ssm_command_failed" {
  name           = "${var.name_prefix}-ssm-command-failed"
  log_group_name = var.lambda_log_group_name
  pattern        = "{ $.event = \"ssm_send_command_failed\" || $.event = \"job_dispatch_failed\" }"

  metric_transformation {
    name          = "${var.name_prefix}-SsmCommandFailedCount"
    namespace     = "TfWin/JobExecution"
    value         = "1"
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "ssm_command_failed" {
  alarm_name          = "${var.name_prefix}-ssm-command-failed"
  alarm_description   = "SSM Run Commandの発行に失敗した場合に検知する"
  namespace           = "TfWin/JobExecution"
  metric_name         = "${var.name_prefix}-SsmCommandFailedCount"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

# --- ジョブ(Launcher)異常終了検知 ---
# LauncherがJobログへ "job_failed"(アプリ異常終了・出力未生成・入力不存在等)を
# 出力する前提のメトリクスフィルタ。Launcher側の実装はREADME参照。
resource "aws_cloudwatch_log_metric_filter" "job_failed" {
  name           = "${var.name_prefix}-job-failed"
  log_group_name = var.job_log_group_name
  pattern        = "{ $.status = \"FAILED\" }"

  metric_transformation {
    name          = "${var.name_prefix}-JobFailedCount"
    namespace     = "TfWin/JobExecution"
    value         = "1"
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "job_failed" {
  alarm_name          = "${var.name_prefix}-job-failed"
  alarm_description   = "Windowsアプリケーションのジョブ実行が失敗(異常終了/出力未生成/入力不存在等)した場合に検知する"
  namespace           = "TfWin/JobExecution"
  metric_name         = "${var.name_prefix}-JobFailedCount"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

# --- SSM Agent異常(Ping状態)検知 ---
resource "aws_cloudwatch_metric_alarm" "ssm_agent_ping" {
  for_each = toset(var.instance_ids)

  alarm_name          = "${var.name_prefix}-ssm-agent-offline-${each.value}"
  alarm_description   = "EC2インスタンス(${each.value})のSSM Agentがオフラインの場合に検知する"
  namespace           = "AWS/SSM-RunCommand"
  metric_name         = "CommandsFailed"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.evaluation_periods
  period              = var.period_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}
