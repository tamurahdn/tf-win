locals {
  # プロジェクト全体で利用する共通タグ。全リソースにデフォルトタグとして付与する。
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }

  name_prefix = "${var.project_name}-${var.environment}"
}
