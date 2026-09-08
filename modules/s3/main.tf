data "aws_caller_identity" "current" {}

# バケット名のグローバル一意性を担保するためアカウントIDを付与する。
resource "aws_s3_bucket" "this" {
  for_each      = var.bucket_names
  bucket        = "${var.name_prefix}-${each.value}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}-${each.value}"
    Purpose = each.key
  })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = var.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id

  rule {
    id     = "default-lifecycle"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.lifecycle_transition_ia_days > 0 ? [1] : []
      content {
        days          = var.lifecycle_transition_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
