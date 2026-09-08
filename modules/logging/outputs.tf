output "log_group_names" {
  description = "作成したロググループの論理名 => ロググループ名のマップ"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "log_group_arns" {
  description = "作成したロググループの論理名 => ARNのマップ"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.arn }
}
