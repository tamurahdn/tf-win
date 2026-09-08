variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "bucket_names" {
  description = "作成するS3バケットの論理名 => 名前サフィックスのマップ"
  type        = map(string)
}

variable "kms_key_arn" {
  description = "バケット暗号化に利用するKMSキーARN"
  type        = string
}

variable "force_destroy" {
  description = "terraform destroy時にオブジェクトごと削除するか"
  type        = bool
  default     = false
}

variable "lifecycle_expiration_days" {
  description = "オブジェクトの自動削除日数(0以下で無効)"
  type        = number
  default     = 0
}

variable "lifecycle_transition_ia_days" {
  description = "STANDARD_IAへの移行日数(0以下で無効)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
