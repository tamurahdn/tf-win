output "ec2_role_arn" {
  description = "Windows EC2用IAMロールARN"
  value       = aws_iam_role.ec2.arn
}

output "ec2_role_name" {
  description = "Windows EC2用IAMロール名"
  value       = aws_iam_role.ec2.name
}

output "ec2_instance_profile_name" {
  description = "Windows EC2用インスタンスプロファイル名"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_instance_profile_arn" {
  description = "Windows EC2用インスタンスプロファイルARN"
  value       = aws_iam_instance_profile.ec2.arn
}
