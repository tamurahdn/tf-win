variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "instance_type" {
  description = "EC2インスタンスタイプ"
  type        = string
}

variable "instance_count" {
  description = "起動台数"
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "EC2を配置するSubnet IDリスト(instance_countに応じてラウンドロビンで割り当て)"
  type        = list(string)
}

variable "security_group_id" {
  description = "EC2に割り当てるセキュリティグループID"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "アタッチするIAMインスタンスプロファイル名"
  type        = string
}

variable "kms_key_id" {
  description = "EBS暗号化に利用するKMSキーID"
  type        = string
}

variable "root_volume_size" {
  description = "ルートEBSボリュームサイズ(GiB)"
  type        = number
  default     = 100
}

variable "root_volume_type" {
  description = "ルートEBSボリュームタイプ"
  type        = string
  default     = "gp3"
}

variable "key_pair_name" {
  description = "キーペア名(RDP用、不要ならnull)"
  type        = string
  default     = null
}

variable "setup_script_execution_mode" {
  description = "初期セットアップスクリプトの実行方式: userdata, ssm_run_command, state_manager"
  type        = string
}

variable "scripts_bucket_name" {
  description = "セットアップスクリプトが格納されたS3バケット名(UserData経由取得に利用)"
  type        = string
}

variable "setup_script_s3_key" {
  description = "セットアップスクリプトのS3キー"
  type        = string
}

variable "cloudwatch_agent_config_ssm_param_name" {
  description = "CloudWatch Agent設定を格納するSSMパラメータ名"
  type        = string
}

variable "fsx_dns_name" {
  description = "FSxのDNS名(UserData内で共有フォルダ参照用に環境変数として渡す)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
