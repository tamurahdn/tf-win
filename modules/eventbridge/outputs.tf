output "rule_name" {
  description = "作成したEventBridgeルール名"
  value       = aws_cloudwatch_event_rule.object_created.name
}

output "rule_arn" {
  description = "作成したEventBridgeルールARN"
  value       = aws_cloudwatch_event_rule.object_created.arn
}
