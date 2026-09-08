output "state_machine_arn" {
  description = "Step FunctionsステートマシンARN"
  value       = aws_sfn_state_machine.job_orchestration.arn
}

output "state_machine_name" {
  description = "Step Functionsステートマシン名"
  value       = aws_sfn_state_machine.job_orchestration.name
}

output "eventbridge_role_arn" {
  description = "EventBridgeがこのステートマシンを起動するためのIAMロールARN"
  value       = aws_iam_role.eventbridge_invoke.arn
}
