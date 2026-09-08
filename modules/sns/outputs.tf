output "topic_arn" {
  description = "作成したSNSトピックARN(未作成時はnull)"
  value       = var.enable_notifications ? aws_sns_topic.this[0].arn : null
}
