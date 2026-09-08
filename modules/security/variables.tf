variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "kms_deletion_window_in_days" {
  description = "KMSキー削除保留期間(日)"
  type        = number
  default     = 30
}

variable "enable_rdp_access" {
  description = "RDP(3389)を許可するか"
  type        = bool
  default     = false
}

variable "rdp_allowed_cidrs" {
  description = "RDPアクセスを許可するCIDRリスト"
  type        = list(string)
  default     = []
}

variable "enable_bastion" {
  description = "踏み台を作成するか(踏み台SGからのRDPをEC2 SGへ許可する)"
  type        = bool
  default     = false
}

variable "create_app_secret" {
  description = "アプリケーション用Secrets Managerシークレットを作成するか"
  type        = bool
  default     = true
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
