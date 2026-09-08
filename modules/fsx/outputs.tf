output "file_system_id" {
  description = "FSxファイルシステムID"
  value       = aws_fsx_windows_file_system.this.id
}

output "dns_name" {
  description = "FSxのDNS名(SMB共有先 \\\\<dns_name>\\share)"
  value       = aws_fsx_windows_file_system.this.dns_name
}

output "preferred_file_server_ip" {
  description = "優先ファイルサーバーIP"
  value       = aws_fsx_windows_file_system.this.preferred_file_server_ip
}
