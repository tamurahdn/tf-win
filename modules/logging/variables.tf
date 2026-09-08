variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "log_retention_in_days" {
  description = "CloudWatch Logsの保持期間(日)"
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "ロググループ暗号化に利用するKMSキーARN"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
