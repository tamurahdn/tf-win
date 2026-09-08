output "instance_ids" {
  description = "作成したEC2インスタンスIDリスト"
  value       = aws_instance.this[*].id
}

output "private_ips" {
  description = "EC2のプライベートIPリスト"
  value       = aws_instance.this[*].private_ip
}

output "ami_id" {
  description = "利用した最新Windows Server 2022 AMI ID"
  value       = local.ami_id
}
