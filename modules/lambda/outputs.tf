output "function_name" {
  description = "Lambda関数名"
  value       = aws_lambda_function.job_dispatcher.function_name
}

output "function_arn" {
  description = "Lambda関数ARN"
  value       = aws_lambda_function.job_dispatcher.arn
}

output "function_invoke_arn" {
  description = "Lambda関数の invoke ARN(EventBridge/Step Functionsターゲット指定用)"
  value       = aws_lambda_function.job_dispatcher.invoke_arn
}

output "log_group_name" {
  description = "Lambda用CloudWatch Logsロググループ名"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "role_arn" {
  description = "Lambda実行ロールARN"
  value       = aws_iam_role.lambda.arn
}
