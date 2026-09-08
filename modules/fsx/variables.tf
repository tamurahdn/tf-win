variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "subnet_ids" {
  description = "FSxを配置するSubnet IDリスト(SINGLE_AZは1つ、MULTI_AZは2つ指定)"
  type        = list(string)
}

variable "security_group_id" {
  description = "FSxに割り当てるセキュリティグループID"
  type        = string
}

variable "kms_key_id" {
  description = "FSx暗号化に利用するKMSキーID"
  type        = string
}

variable "storage_capacity" {
  description = "ストレージ容量(GiB)"
  type        = number
  default     = 300
}

variable "throughput_capacity" {
  description = "スループットキャパシティ(MB/s)"
  type        = number
  default     = 128
}

variable "storage_type" {
  description = "ストレージタイプ(SSD or HDD)"
  type        = string
  default     = "SSD"
}

variable "deployment_type" {
  description = "デプロイタイプ(SINGLE_AZ_1, SINGLE_AZ_2, MULTI_AZ_1)"
  type        = string
  default     = "SINGLE_AZ_2"
}

variable "automatic_backup_retention_days" {
  description = "自動バックアップ保持日数"
  type        = number
  default     = 7
}

variable "daily_automatic_backup_start_time" {
  description = "自動バックアップ開始時刻(HH:MM, UTC)"
  type        = string
  default     = "17:00" # JST 02:00
}

variable "weekly_maintenance_start_time" {
  description = "週次メンテナンス開始時刻(d:HH:MM, UTC)"
  type        = string
  default     = "7:18:00" # 日曜 JST03:00
}

variable "self_managed_active_directory" {
  description = <<-EOT
    FSx for Windows File Serverの参加先ActiveDirectory設定。
    FSx for Windows File ServerはAD参加が必須のため、既存のAWS Managed Microsoft AD
    または自己管理ADのいずれかを指定する。将来AWS Managed Microsoft ADモジュールを
    追加した場合はそちらの出力値をここに渡す。
  EOT
  type = object({
    dns_ips                                = list(string)
    domain_name                            = string
    password                               = string
    username                               = string
    file_system_administrators_group       = optional(string, "Domain Admins")
    organizational_unit_distinguished_name = optional(string)
  })
  default = null
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
