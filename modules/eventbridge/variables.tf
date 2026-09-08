variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

variable "input_bucket_name" {
  description = "監視対象のS3 Inputバケット名"
  type        = string
}

variable "input_key_prefix" {
  description = "イベント対象を絞り込むオブジェクトキーのプレフィックス(空文字で全オブジェクト対象)"
  type        = string
  default     = ""
}

variable "target_lambda_arn" {
  description = "イベント発生時に起動するLambda関数ARN(Step Functions未使用時)"
  type        = string
  default     = null
}

variable "target_lambda_name" {
  description = "イベント発生時に起動するLambda関数名(Lambdaへのinvoke許可付与に利用)"
  type        = string
  default     = null
}

variable "target_state_machine_arn" {
  description = "イベント発生時に起動するStep Functions ステートマシンARN(Step Functions使用時)"
  type        = string
  default     = null
}

variable "use_step_functions" {
  description = "trueの場合Step Functionsをターゲットにする。falseの場合Lambdaを直接ターゲットにする。"
  type        = bool
  default     = false
}

variable "eventbridge_target_role_arn" {
  description = "EventBridgeがStep Functionsを起動するためのIAMロールARN(use_step_functions=true時に必須)"
  type        = string
  default     = null
}

variable "dlq_arn" {
  description = "イベント配信失敗時のデッドレターキュー(SQS)ARN。未指定の場合はDLQなし。"
  type        = string
  default     = null
}

variable "max_event_age_seconds" {
  description = "イベントの最大保持時間(秒)。これを超えると配信を諦めDLQへ送るか破棄する。"
  type        = number
  default     = 3600
}

variable "retry_attempts" {
  description = "ターゲット起動失敗時の最大リトライ回数"
  type        = number
  default     = 3
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
