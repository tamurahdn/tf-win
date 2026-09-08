variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
}

variable "availability_zones" {
  description = "利用するAZのリスト"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public SubnetのCIDRリスト"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private SubnetのCIDRリスト"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "NAT Gatewayを作成するか"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "NAT Gatewayを1つに集約するか"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "SSM/S3等のVPCエンドポイントを作成するか"
  type        = bool
  default     = true
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
