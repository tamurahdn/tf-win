variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "s3_bucket_arns" {
  description = "EC2からアクセスを許可するS3バケットARNのリスト"
  type        = list(string)
}

variable "fsx_arn" {
  description = "アクセスを許可するFSxファイルシステムARN"
  type        = string
}

variable "kms_key_arn" {
  description = "EC2から利用を許可するKMSキーARN"
  type        = string
}

variable "secret_arns" {
  description = "EC2から読み取りを許可するSecrets ManagerシークレットARNのリスト"
  type        = list(string)
  default     = []
}

variable "log_group_arns" {
  description = "EC2から書き込みを許可するCloudWatch LogsロググループARNのリスト"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
