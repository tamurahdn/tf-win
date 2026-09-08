variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "lambda_function_arn" {
  description = "ジョブ投入(SSM SendCommand)を行うLambda関数ARN"
  type        = string
}

variable "log_group_arn" {
  description = "ステートマシン実行ログを出力するCloudWatch LogsロググループARN"
  type        = string
}

variable "log_group_name" {
  description = "ステートマシン実行ログを出力するCloudWatch Logsロググループ名"
  type        = string
}

variable "job_status_log_group_name" {
  description = "ジョブの最終状態(成功/失敗/タイムアウト)を記録するCloudWatch Logsロググループ名"
  type        = string
}

variable "poll_interval_seconds" {
  description = "SSMコマンド実行状況をポーリングする間隔(秒)"
  type        = number
  default     = 15
}

variable "max_poll_attempts" {
  description = "SSMコマンド実行状況の最大ポーリング回数(poll_interval_seconds x max_poll_attempts が実質タイムアウトの目安)"
  type        = number
  default     = 240 # 15秒 x 240 = 60分
}

variable "kms_key_arn" {
  description = "ステートマシンログ暗号化に利用するKMSキーARN"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
