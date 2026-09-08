variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "lambda_function_name" {
  description = "監視対象のLambda関数名(Job Dispatcher)"
  type        = string
}

variable "lambda_timeout_seconds" {
  description = "Lambdaのタイムアウト秒数(Duration近接アラームの閾値算出に利用)"
  type        = number
}

variable "lambda_log_group_name" {
  description = "Lambdaが出力するCloudWatch Logsロググループ名(構造化ログのメトリクスフィルタ用)"
  type        = string
}

variable "job_log_group_name" {
  description = "Launcherが出力するジョブ実行ログのCloudWatch Logsロググループ名"
  type        = string
}

variable "instance_ids" {
  description = "SSM Ping状態(EC2オフライン検知)監視対象インスタンスIDリスト"
  type        = list(string)
}

variable "sns_topic_arn" {
  description = "アラーム通知先SNSトピックARN(未使用の場合はnull)"
  type        = string
  default     = null
}

variable "evaluation_periods" {
  description = "アラーム評価期間の回数"
  type        = number
  default     = 1
}

variable "period_seconds" {
  description = "メトリクス集計期間(秒)"
  type        = number
  default     = 300
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
