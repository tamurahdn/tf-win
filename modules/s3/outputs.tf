output "bucket_ids" {
  description = "作成したバケットの論理名 => バケット名のマップ"
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  description = "作成したバケットの論理名 => ARNのマップ"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}
