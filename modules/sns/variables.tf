variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "topic_suffix" {
  description = "トピック名のサフィックス(用途別に複数トピックを作成する場合に利用)"
  type        = string
  default     = "alarms"
}

variable "enable_notifications" {
  description = "SNS通知を有効にするか"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "通知先メールアドレス(空文字の場合はEmail Subscriptionを作成しない)"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "トピック暗号化に利用するKMSキーARN"
  type        = string
}

variable "allow_eventbridge_publish" {
  description = "EventBridgeからのPublishを許可するか"
  type        = bool
  default     = true
}

variable "allow_cloudwatch_publish" {
  description = "CloudWatch Alarmからのpublishを許可するか(CloudWatch Alarmは標準でSNS Publish可能なため通常true)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
