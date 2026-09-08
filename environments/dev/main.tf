terraform {
  required_version = ">= 1.9.0"

  # リモートステート管理を推奨する。バケット名・キーは環境ごとに必ず変更すること。
  # 初回terraform init前にS3バケット・DynamoDBテーブル(ロック用)を用意しておく必要がある。
  backend "s3" {
    bucket         = "REPLACE_WITH_YOUR_TFSTATE_BUCKET"
    key            = "tf-win/dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "REPLACE_WITH_YOUR_TFSTATE_LOCK_TABLE"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

module "tf_win" {
  source = "../../"

  project_name = var.project_name
  environment  = "dev"
  owner        = var.owner
  aws_region   = var.aws_region
  aws_profile  = var.aws_profile

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints

  ec2_instance_type            = var.ec2_instance_type
  ec2_instance_count           = var.ec2_instance_count
  ec2_root_volume_size         = var.ec2_root_volume_size
  ec2_root_volume_type         = var.ec2_root_volume_type
  ec2_key_pair_name            = var.ec2_key_pair_name
  ec2_deploy_in_private_subnet = var.ec2_deploy_in_private_subnet
  enable_rdp_access            = var.enable_rdp_access
  rdp_allowed_cidrs            = var.rdp_allowed_cidrs
  enable_bastion               = var.enable_bastion
  bastion_allowed_cidrs        = var.bastion_allowed_cidrs
  setup_script_execution_mode  = var.setup_script_execution_mode
  setup_script_s3_key          = var.setup_script_s3_key

  enable_fsx                        = var.enable_fsx
  fsx_storage_capacity              = var.fsx_storage_capacity
  fsx_throughput_capacity           = var.fsx_throughput_capacity
  fsx_storage_type                  = var.fsx_storage_type
  fsx_deployment_type               = var.fsx_deployment_type
  fsx_shared_folders                = var.fsx_shared_folders
  fsx_self_managed_active_directory = var.fsx_self_managed_active_directory

  s3_bucket_names                 = var.s3_bucket_names
  s3_force_destroy                = var.s3_force_destroy
  s3_lifecycle_expiration_days    = var.s3_lifecycle_expiration_days
  s3_lifecycle_transition_ia_days = var.s3_lifecycle_transition_ia_days

  kms_deletion_window_in_days = var.kms_deletion_window_in_days
  create_app_secret           = var.create_app_secret

  enable_sns_notifications = var.enable_sns_notifications
  sns_notification_email   = var.sns_notification_email
  alarm_cpu_threshold      = var.alarm_cpu_threshold
  alarm_memory_threshold   = var.alarm_memory_threshold
  alarm_disk_threshold     = var.alarm_disk_threshold
  log_retention_in_days    = var.log_retention_in_days
}
