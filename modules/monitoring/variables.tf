variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "instance_ids" {
  description = "監視対象EC2インスタンスIDリスト"
  type        = list(string)
}

variable "fsx_file_system_id" {
  description = "監視対象FSxファイルシステムID"
  type        = string
}

variable "alarm_cpu_threshold" {
  description = "CPU使用率アラーム閾値(%)"
  type        = number
  default     = 80
}

variable "alarm_memory_threshold" {
  description = "メモリ使用率アラーム閾値(%)"
  type        = number
  default     = 80
}

variable "alarm_disk_threshold" {
  description = "ディスク使用率アラーム閾値(%)"
  type        = number
  default     = 80
}

variable "enable_sns_notifications" {
  description = "SNS通知を有効にするか"
  type        = bool
  default     = false
}

variable "sns_notification_email" {
  description = "SNS通知先メールアドレス"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "SNSトピック暗号化に利用するKMSキーARN"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
