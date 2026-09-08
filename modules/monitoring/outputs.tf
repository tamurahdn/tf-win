output "sns_topic_arn" {
  description = "アラーム通知用SNSトピックARN(未作成時はnull)"
  value       = var.enable_sns_notifications ? aws_sns_topic.alarms[0].arn : null
}
