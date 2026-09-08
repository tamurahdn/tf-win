output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private Subnet IDリスト"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public Subnet IDリスト"
  value       = module.network.public_subnet_ids
}

output "ec2_instance_ids" {
  description = "Windows EC2のインスタンスIDリスト"
  value       = module.ec2.instance_ids
}

output "ec2_private_ips" {
  description = "Windows EC2のプライベートIPリスト"
  value       = module.ec2.private_ips
}

output "fsx_dns_name" {
  description = "FSxのDNS名(SMB共有先)"
  value       = var.enable_fsx ? module.fsx[0].dns_name : null
}

output "s3_bucket_ids" {
  description = "作成したS3バケットの論理名 => バケット名のマップ"
  value       = module.s3.bucket_ids
}

output "kms_key_arn" {
  description = "共通KMSキーARN"
  value       = module.security.kms_key_arn
}

output "app_secret_arn" {
  description = "アプリケーション用Secrets ManagerシークレットARN"
  value       = module.security.app_secret_arn
}

output "cloudwatch_log_group_names" {
  description = "CloudWatch Logsロググループ名のマップ"
  value       = module.logging.log_group_names
}

output "sns_topic_arn" {
  description = "アラーム通知用SNSトピックARN"
  value       = module.monitoring.sns_topic_arn
}
