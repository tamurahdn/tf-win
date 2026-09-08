variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "setup_script_execution_mode" {
  description = "初期セットアップスクリプトの実行方式: userdata, ssm_run_command, state_manager"
  type        = string
}

variable "scripts_bucket_name" {
  description = "セットアップスクリプトが格納されたS3バケット名"
  type        = string
}

variable "setup_script_s3_key" {
  description = "セットアップスクリプトのS3キー"
  type        = string
}

variable "instance_ids" {
  description = "SSM Run Command / State Managerの対象EC2インスタンスIDリスト(ssm_run_command/state_manager選択時のみ利用)"
  type        = list(string)
  default     = []
}

variable "output_s3_bucket_name" {
  description = "State Manager(SSM Association)の実行結果出力先S3バケット名(logsバケットを想定)"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
