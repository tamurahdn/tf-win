output "ssm_document_name" {
  description = "作成したSSMドキュメント名(userdataモードの場合はnull)"
  value       = var.setup_script_execution_mode != "userdata" ? aws_ssm_document.run_setup_script[0].name : null
}

output "job_launcher_document_name" {
  description = "ジョブ実行用(Launcher起動)SSMドキュメント名"
  value       = aws_ssm_document.run_job_launcher.name
}

output "job_launcher_document_arn" {
  description = "ジョブ実行用(Launcher起動)SSMドキュメントARN"
  value       = aws_ssm_document.run_job_launcher.arn
}
