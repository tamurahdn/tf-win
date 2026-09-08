output "ssm_command_failed_alarm_arn" {
  description = "SSM Run Command失敗アラームARN"
  value       = aws_cloudwatch_metric_alarm.ssm_command_failed.arn
}

output "job_failed_alarm_arn" {
  description = "ジョブ実行失敗アラームARN"
  value       = aws_cloudwatch_metric_alarm.job_failed.arn
}
