output "kms_key_id" {
  description = "共通KMSキーID"
  value       = aws_kms_key.this.key_id
}

output "kms_key_arn" {
  description = "共通KMSキーARN"
  value       = aws_kms_key.this.arn
}

output "ec2_security_group_id" {
  description = "Windows EC2用セキュリティグループID"
  value       = aws_security_group.ec2.id
}

output "fsx_security_group_id" {
  description = "FSx用セキュリティグループID"
  value       = aws_security_group.fsx.id
}

output "bastion_security_group_id" {
  description = "踏み台用セキュリティグループID(未作成時はnull)"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
}

output "app_secret_arn" {
  description = "アプリケーション用Secrets ManagerシークレットARN(未作成時はnull)"
  value       = var.create_app_secret ? aws_secretsmanager_secret.app[0].arn : null
}
