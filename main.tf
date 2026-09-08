# ==================================================================
# ルートモジュール: 各モジュールを結線する
# 実際のリソースは全て modules/ 配下に定義し、ここでは
# environments/<env> から渡された変数をもとにモジュールを呼び出すのみとする。
# ==================================================================

module "network" {
  source = "./modules/network"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
  tags                 = local.common_tags
}

module "security" {
  source = "./modules/security"

  name_prefix                 = local.name_prefix
  vpc_id                      = module.network.vpc_id
  vpc_cidr                    = var.vpc_cidr
  kms_deletion_window_in_days = var.kms_deletion_window_in_days
  enable_rdp_access           = var.enable_rdp_access
  rdp_allowed_cidrs           = var.rdp_allowed_cidrs
  enable_bastion              = var.enable_bastion
  create_app_secret           = var.create_app_secret
  tags                        = local.common_tags
}

module "logging" {
  source = "./modules/logging"

  name_prefix           = local.name_prefix
  log_retention_in_days = var.log_retention_in_days
  kms_key_arn           = module.security.kms_key_arn
  tags                  = local.common_tags
}

module "s3" {
  source = "./modules/s3"

  name_prefix                  = local.name_prefix
  bucket_names                 = var.s3_bucket_names
  kms_key_arn                  = module.security.kms_key_arn
  force_destroy                = var.s3_force_destroy
  lifecycle_expiration_days    = var.s3_lifecycle_expiration_days
  lifecycle_transition_ia_days = var.s3_lifecycle_transition_ia_days
  tags                         = local.common_tags
}

module "fsx" {
  source = "./modules/fsx"
  count  = var.enable_fsx ? 1 : 0

  name_prefix         = local.name_prefix
  subnet_ids          = var.fsx_deployment_type == "MULTI_AZ_1" ? module.network.private_subnet_ids : [module.network.private_subnet_ids[0]]
  security_group_id   = module.security.fsx_security_group_id
  kms_key_id          = module.security.kms_key_id
  storage_capacity    = var.fsx_storage_capacity
  throughput_capacity = var.fsx_throughput_capacity
  storage_type        = var.fsx_storage_type
  deployment_type     = var.fsx_deployment_type

  self_managed_active_directory = var.fsx_self_managed_active_directory

  tags = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix    = local.name_prefix
  s3_bucket_arns = values(module.s3.bucket_arns)
  fsx_arn        = var.enable_fsx ? module.fsx[0].file_system_id : ""
  kms_key_arn    = module.security.kms_key_arn
  secret_arns    = module.security.app_secret_arn != null ? [module.security.app_secret_arn] : []
  log_group_arns = values(module.logging.log_group_arns)
  tags           = local.common_tags
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "/${local.name_prefix}/cloudwatch-agent/config"
  description = "CloudWatch Agent設定(Windows Event Log, PowerShellログ, メモリ/ディスクメトリクス等)"
  type        = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
    }
    metrics = {
      metrics_collected = {
        Memory = {
          measurement = ["% Committed Bytes In Use"]
        }
        LogicalDisk = {
          measurement = ["% Free Space"]
          resources   = ["C:"]
        }
      }
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
    }
    logs = {
      logs_collected = {
        windows_events = {
          collect_list = [
            {
              event_name      = "System"
              event_format    = "xml"
              event_levels    = ["INFORMATION", "WARNING", "ERROR", "CRITICAL"]
              log_group_name  = module.logging.log_group_names["system_event"]
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "Application"
              event_format    = "xml"
              event_levels    = ["INFORMATION", "WARNING", "ERROR", "CRITICAL"]
              log_group_name  = module.logging.log_group_names["application"]
              log_stream_name = "{instance_id}"
            },
            {
              event_name      = "Security"
              event_format    = "xml"
              event_levels    = ["INFORMATION", "WARNING", "ERROR", "CRITICAL"]
              log_group_name  = module.logging.log_group_names["security_event"]
              log_stream_name = "{instance_id}"
            }
          ]
        }
        files = {
          collect_list = [
            {
              file_path       = "C:\\ProgramData\\Amazon\\setup-userdata.log"
              log_group_name  = module.logging.log_group_names["setup"]
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "C:\\PSLogs\\*.log"
              log_group_name  = module.logging.log_group_names["powershell"]
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  })

  tags = local.common_tags
}

module "ec2" {
  source = "./modules/ec2"

  name_prefix                            = local.name_prefix
  instance_type                          = var.ec2_instance_type
  instance_count                         = var.ec2_instance_count
  subnet_ids                             = var.ec2_deploy_in_private_subnet ? module.network.private_subnet_ids : module.network.public_subnet_ids
  security_group_id                      = module.security.ec2_security_group_id
  iam_instance_profile_name              = module.iam.ec2_instance_profile_name
  kms_key_id                             = module.security.kms_key_id
  root_volume_size                       = var.ec2_root_volume_size
  root_volume_type                       = var.ec2_root_volume_type
  key_pair_name                          = var.ec2_key_pair_name
  setup_script_execution_mode            = var.setup_script_execution_mode
  scripts_bucket_name                    = module.s3.bucket_ids["scripts"]
  setup_script_s3_key                    = var.setup_script_s3_key
  cloudwatch_agent_config_ssm_param_name = aws_ssm_parameter.cloudwatch_agent_config.name
  fsx_dns_name                           = var.enable_fsx ? module.fsx[0].dns_name : ""

  tags = local.common_tags
}

module "ssm" {
  source = "./modules/ssm"

  name_prefix                 = local.name_prefix
  setup_script_execution_mode = var.setup_script_execution_mode
  scripts_bucket_name         = module.s3.bucket_ids["scripts"]
  setup_script_s3_key         = var.setup_script_s3_key
  instance_ids                = module.ec2.instance_ids
  output_s3_bucket_name       = module.s3.bucket_ids["logs"]

  tags = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix              = local.name_prefix
  instance_ids             = module.ec2.instance_ids
  fsx_file_system_id       = var.enable_fsx ? module.fsx[0].file_system_id : ""
  alarm_cpu_threshold      = var.alarm_cpu_threshold
  alarm_memory_threshold   = var.alarm_memory_threshold
  alarm_disk_threshold     = var.alarm_disk_threshold
  enable_sns_notifications = var.enable_sns_notifications
  sns_notification_email   = var.sns_notification_email
  kms_key_arn              = module.security.kms_key_arn

  tags = local.common_tags
}
