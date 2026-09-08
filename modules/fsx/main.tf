# FSx for Windows File Server
#
# AD参加が必須のサービスであるため、self_managed_active_directory変数で
# ドメイン情報を渡す運用とする(本番ではAWS Managed Microsoft ADと連携させる想定)。
# 開発検証などAD無しで確認したい場合はaws_directory_service_directoryを別途用意するか、
# 本モジュールをスキップして代替(EFS等)を検討すること。

resource "aws_fsx_windows_file_system" "this" {
  storage_capacity    = var.storage_capacity
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]
  throughput_capacity = var.throughput_capacity
  storage_type        = var.storage_type
  deployment_type     = var.deployment_type
  kms_key_id          = var.kms_key_id

  automatic_backup_retention_days   = var.automatic_backup_retention_days
  daily_automatic_backup_start_time = var.daily_automatic_backup_start_time
  weekly_maintenance_start_time     = var.weekly_maintenance_start_time

  # MULTI_AZの場合は優先Subnetの指定が必要
  preferred_subnet_id = var.deployment_type == "MULTI_AZ_1" ? var.subnet_ids[0] : null

  dynamic "self_managed_active_directory" {
    for_each = var.self_managed_active_directory != null ? [var.self_managed_active_directory] : []
    content {
      dns_ips                                = self_managed_active_directory.value.dns_ips
      domain_name                            = self_managed_active_directory.value.domain_name
      password                               = self_managed_active_directory.value.password
      username                               = self_managed_active_directory.value.username
      file_system_administrators_group       = self_managed_active_directory.value.file_system_administrators_group
      organizational_unit_distinguished_name = self_managed_active_directory.value.organizational_unit_distinguished_name
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-fsx"
  })

  lifecycle {
    precondition {
      condition     = var.self_managed_active_directory != null
      error_message = "FSx for Windows File ServerはActiveDirectory参加が必須です。self_managed_active_directory変数を設定してください(AWS Managed Microsoft AD等を別途構築の上、その接続情報を渡してください)。"
    }
  }
}
