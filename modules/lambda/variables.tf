variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "ssm_document_name" {
  description = "Launcher起動用SSMドキュメント名(ssmモジュールのjob_launcherドキュメント)"
  type        = string
}

variable "target_instance_ids" {
  description = "SSM Run Commandの実行対象インスタンスIDリスト(空の場合はタグターゲットを利用)"
  type        = list(string)
  default     = []
}

variable "target_tag_key" {
  description = "SSM Run Commandの実行対象をタグで指定する場合のタグキー"
  type        = string
  default     = "JobWorker"
}

variable "target_tag_value" {
  description = "SSM Run Commandの実行対象をタグで指定する場合のタグ値"
  type        = string
  default     = "true"
}

variable "output_bucket_name" {
  description = "Outputバケット名(Launcherへ渡すパラメータとして環境変数経由で伝搬)"
  type        = string
}

variable "logs_bucket_name" {
  description = "Logsバケット名(Launcherへ渡すパラメータとして環境変数経由で伝搬)"
  type        = string
}

variable "fsx_workspace_share" {
  description = "FSxのWorkspace共有パス(参考情報としてLambda環境変数に渡す。Lambda自体はFSxへ直接アクセスしない)"
  type        = string
  default     = ""
}

variable "app_config_name" {
  description = "Launcherが参照するアプリケーション設定名(config/<name>.json 等の切り替えキー)"
  type        = string
  default     = "sample-uppercase"
}

variable "command_timeout_seconds" {
  description = "SSM Run Commandのタイムアウト秒数"
  type        = number
  default     = 3600
}

variable "lambda_timeout_seconds" {
  description = "Lambda関数自体のタイムアウト秒数(SSM SendCommand呼び出しのみのため短時間で十分)"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambdaのメモリサイズ(MB)"
  type        = number
  default     = 128
}

variable "log_retention_in_days" {
  description = "Lambda用CloudWatch Logsの保持期間(日)"
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "Lambda環境変数・ログ暗号化に利用するKMSキーARN"
  type        = string
}

variable "reserved_concurrent_executions" {
  description = "Lambdaの同時実行数上限(-1で無制限)。Windows EC2側の処理能力に合わせて過剰なジョブ投入を抑止する。"
  type        = number
  default     = 5
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
