output "ssm_document_name" {
  description = "作成したSSMドキュメント名(userdataモードの場合はnull)"
  value       = var.setup_script_execution_mode != "userdata" ? aws_ssm_document.run_setup_script[0].name : null
}
