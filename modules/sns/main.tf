# 汎用SNS通知モジュール
# monitoringモジュール(EC2/FSx関連アラーム)、Lambda/SSM関連アラーム双方から
# 再利用できるよう、通知トピックの作成ロジックを独立モジュール化している。

resource "aws_sns_topic" "this" {
  count             = var.enable_notifications ? 1 : 0
  name              = "${var.name_prefix}-${var.topic_suffix}"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${var.topic_suffix}"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.this[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

data "aws_iam_policy_document" "topic_policy" {
  count = var.enable_notifications ? 1 : 0

  statement {
    sid    = "AllowCloudWatchAlarmPublish"
    effect = var.allow_cloudwatch_publish ? "Allow" : "Deny"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this[0].arn]
  }

  dynamic "statement" {
    for_each = var.allow_eventbridge_publish ? [1] : []
    content {
      sid    = "AllowEventBridgePublish"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.this[0].arn]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  count  = var.enable_notifications ? 1 : 0
  arn    = aws_sns_topic.this[0].arn
  policy = data.aws_iam_policy_document.topic_policy[0].json
}
