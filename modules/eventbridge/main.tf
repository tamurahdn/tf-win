# S3 Inputバケットへのオブジェクト作成イベントをEventBridge経由で受信し、
# Lambda(またはStep Functions)を起動するルールを定義する。
#
# 前提: S3バケット側で `aws_s3_bucket_notification` の `eventbridge = true` により
# EventBridgeへの通知が有効化されていること(modules/s3側で対応)。

resource "aws_cloudwatch_event_rule" "object_created" {
  name        = "${var.name_prefix}-input-object-created"
  description = "S3 Inputバケットへのオブジェクト作成を検知し、ジョブ実行フローを起動する"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.input_bucket_name]
      }
      object = var.input_key_prefix != "" ? {
        key = [{ prefix = var.input_key_prefix }]
      } : null
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-input-object-created"
  })
}

##############################
# ターゲット: Lambda直接起動 (use_step_functions = false)
##############################

resource "aws_cloudwatch_event_target" "lambda" {
  count = var.use_step_functions ? 0 : 1

  rule      = aws_cloudwatch_event_rule.object_created.name
  target_id = "job-dispatcher-lambda"
  arn       = var.target_lambda_arn

  retry_policy {
    maximum_retry_attempts       = var.retry_attempts
    maximum_event_age_in_seconds = var.max_event_age_seconds
  }

  dynamic "dead_letter_config" {
    for_each = var.dlq_arn != null ? [var.dlq_arn] : []
    content {
      arn = dead_letter_config.value
    }
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.use_step_functions ? 0 : 1

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.target_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.object_created.arn
}

##############################
# ターゲット: Step Functions起動 (use_step_functions = true)
##############################

resource "aws_cloudwatch_event_target" "step_functions" {
  count = var.use_step_functions ? 1 : 0

  rule      = aws_cloudwatch_event_rule.object_created.name
  target_id = "job-orchestration-state-machine"
  arn       = var.target_state_machine_arn
  role_arn  = var.eventbridge_target_role_arn

  retry_policy {
    maximum_retry_attempts       = var.retry_attempts
    maximum_event_age_in_seconds = var.max_event_age_seconds
  }

  dynamic "dead_letter_config" {
    for_each = var.dlq_arn != null ? [var.dlq_arn] : []
    content {
      arn = dead_letter_config.value
    }
  }
}
