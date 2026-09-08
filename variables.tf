##############################
# 共通
##############################

variable "project_name" {
  description = "プロジェクト名。リソース命名・タグに利用する。"
  type        = string
}

variable "environment" {
  description = "環境名 (dev, stg, prod など)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment は dev, stg, prod のいずれかを指定してください。"
  }
}

variable "owner" {
  description = "リソースの管理責任者(部署名・チーム名等)。タグ付けに利用する。"
  type        = string
  default     = "infra-team"
}

variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "Terraform実行時に利用するAWS CLIプロファイル名。CI環境等ではnullにしてIAMロール/環境変数の認証情報を利用する。"
  type        = string
  default     = null
}

##############################
# ネットワーク
##############################

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "利用するAZのリスト"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public SubnetのCIDRリスト(AZ数と対応させる)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private SubnetのCIDRリスト(AZ数と対応させる)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "NAT Gatewayを作成するか(Private SubnetからのSSM/S3等アウトバウンド通信に必要)"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true の場合、コスト削減のためNAT Gatewayを1つに集約する(可用性は低下)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "SSM/S3等のVPCエンドポイントを作成するか(NATを介さない経路を用意しセキュリティ・コストを最適化)"
  type        = bool
  default     = true
}

##############################
# EC2 (Windows)
##############################

variable "ec2_instance_type" {
  description = "Windows EC2のインスタンスタイプ"
  type        = string
  default     = "m5.xlarge"
}

variable "ec2_instance_count" {
  description = "起動するWindows EC2の台数"
  type        = number
  default     = 1
}

variable "ec2_root_volume_size" {
  description = "ルートEBSボリュームサイズ(GiB)"
  type        = number
  default     = 100
}

variable "ec2_root_volume_type" {
  description = "ルートEBSボリュームタイプ"
  type        = string
  default     = "gp3"
}

variable "ec2_key_pair_name" {
  description = "RDP用キーペア名(不要な場合はnull。Session Manager優先のため通常は未使用)"
  type        = string
  default     = null
}

variable "ec2_deploy_in_private_subnet" {
  description = "trueの場合Private SubnetにEC2を配置する(推奨)"
  type        = bool
  default     = true
}

variable "enable_rdp_access" {
  description = "RDP(3389)を許可するか。既定は無効でSession Manager経由の管理を前提とする。"
  type        = bool
  default     = false
}

variable "rdp_allowed_cidrs" {
  description = "RDPアクセスを許可するCIDRリスト(enable_rdp_access=trueの場合のみ利用)"
  type        = list(string)
  default     = []
}

variable "enable_bastion" {
  description = "踏み台(Bastion)ホストを作成するか"
  type        = bool
  default     = false
}

variable "bastion_allowed_cidrs" {
  description = "踏み台へのRDP/SSHアクセスを許可するCIDRリスト"
  type        = list(string)
  default     = []
}

variable "setup_script_execution_mode" {
  description = "初期セットアップスクリプトの実行方式: userdata, ssm_run_command, state_manager のいずれか"
  type        = string
  default     = "userdata"

  validation {
    condition     = contains(["userdata", "ssm_run_command", "state_manager"], var.setup_script_execution_mode)
    error_message = "setup_script_execution_mode は userdata, ssm_run_command, state_manager のいずれかを指定してください。"
  }
}

variable "setup_script_s3_key" {
  description = "S3(scriptsバケット)に配置する初期セットアップスクリプトのキー(例: bootstrap.ps1)。UserDataやSSMから参照する。"
  type        = string
  default     = "bootstrap.ps1"
}

variable "setup_scripts_local_dir" {
  description = "アップロードするセットアップスクリプトが格納されたローカルディレクトリ(scripts/配下)"
  type        = string
  default     = "../../scripts"
}

##############################
# FSx for Windows File Server
##############################

variable "enable_fsx" {
  description = "FSx for Windows File Serverを作成するか(AD参加が前提のため、AD未整備の環境ではfalseにできる)"
  type        = bool
  default     = true
}

variable "fsx_self_managed_active_directory" {
  description = <<-EOT
    FSxが参加するActiveDirectoryの接続情報。
    AWS Managed Microsoft AD、または既存のオンプレミス/セルフホストADの情報を指定する。
    machineでの平文管理を避けるため、実運用ではSecrets Manager等から取得した値を
    tfvars経由ではなく、CI/CDのシークレット変数として注入することを推奨する。
  EOT
  type = object({
    dns_ips                                = list(string)
    domain_name                            = string
    password                               = string
    username                               = string
    file_system_administrators_group       = optional(string, "Domain Admins")
    organizational_unit_distinguished_name = optional(string)
  })
  default   = null
  sensitive = true
}

variable "fsx_storage_capacity" {
  description = "FSxのストレージ容量(GiB)。SSDは32以上、HDDは2000以上。"
  type        = number
  default     = 300
}

variable "fsx_throughput_capacity" {
  description = "FSxのスループットキャパシティ(MB/s)"
  type        = number
  default     = 128
}

variable "fsx_storage_type" {
  description = "FSxのストレージタイプ(SSD or HDD)"
  type        = string
  default     = "SSD"
}

variable "fsx_deployment_type" {
  description = "FSxのデプロイタイプ(SINGLE_AZ_1, SINGLE_AZ_2, MULTI_AZ_1)"
  type        = string
  default     = "SINGLE_AZ_2"
}

variable "fsx_shared_folders" {
  description = "FSx上に作成する共有フォルダ名の論理リスト(実際のフォルダ作成はセットアップスクリプト側で実施し、ここでは命名規約・出力用に利用)"
  type        = list(string)
  default     = ["Input", "Output", "Workspace", "Temp", "Logs"]
}

variable "fsx_throughput_capacity_multi_az" {
  description = "MULTI_AZ選択時に許可される最小スループット等の調整用(将来拡張用)"
  type        = number
  default     = 128
}

##############################
# S3
##############################

variable "s3_bucket_names" {
  description = "作成するS3バケットの論理名 => 名前サフィックスのマップ"
  type        = map(string)
  default = {
    input     = "input"
    output    = "output"
    scripts   = "scripts"
    logs      = "logs"
    artifacts = "artifacts"
  }
}

variable "s3_force_destroy" {
  description = "terraform destroy時にバケット内オブジェクトごと削除するか(devのみtrue推奨)"
  type        = bool
  default     = false
}

variable "s3_lifecycle_expiration_days" {
  description = "S3オブジェクトの自動削除日数(0以下で無効)"
  type        = number
  default     = 0
}

variable "s3_lifecycle_transition_ia_days" {
  description = "S3オブジェクトをSTANDARD_IAへ移行するまでの日数(0以下で無効)"
  type        = number
  default     = 30
}

##############################
# Secrets Manager / KMS
##############################

variable "kms_deletion_window_in_days" {
  description = "KMSキー削除保留期間(日)"
  type        = number
  default     = 30
}

variable "create_app_secret" {
  description = "アプリケーション用のSecrets Managerシークレットを作成するか"
  type        = bool
  default     = true
}

##############################
# 監視・通知
##############################

variable "enable_sns_notifications" {
  description = "CloudWatch AlarmのSNS通知を有効にするか"
  type        = bool
  default     = false
}

variable "sns_notification_email" {
  description = "SNS通知先メールアドレス(enable_sns_notifications=trueの場合に利用)"
  type        = string
  default     = ""
}

variable "alarm_cpu_threshold" {
  description = "CPU使用率アラームの閾値(%)"
  type        = number
  default     = 80
}

variable "alarm_memory_threshold" {
  description = "メモリ使用率アラームの閾値(%) ※CloudWatch Agent必須"
  type        = number
  default     = 80
}

variable "alarm_disk_threshold" {
  description = "ディスク使用率アラームの閾値(%) ※CloudWatch Agent必須"
  type        = number
  default     = 80
}

variable "log_retention_in_days" {
  description = "CloudWatch Logsの保持期間(日)"
  type        = number
  default     = 90
}

##############################
# イベント駆動ジョブ実行基盤
##############################

variable "enable_event_driven_job_execution" {
  description = "S3→EventBridge→Lambda→SSM→EC2によるイベント駆動ジョブ実行基盤を有効にするか"
  type        = bool
  default     = false
}

variable "use_step_functions" {
  description = "EventBridgeの後続としてStep Functions(ジョブ状態のポーリング管理)を利用するか。falseの場合はLambdaを直接起動する。"
  type        = bool
  default     = false
}

variable "job_input_key_prefix" {
  description = "EventBridgeルールでフィルタする入力S3キーのプレフィックス(空文字で全キー対象)"
  type        = string
  default     = ""
}

variable "target_tag_key" {
  description = "SSM Run Commandの対象をタグで指定する場合のタグキー(instance_idsを利用する場合は空でよい)"
  type        = string
  default     = "Role"
}

variable "target_tag_value" {
  description = "SSM Run Commandの対象をタグで指定する場合のタグ値"
  type        = string
  default     = "tf-win-worker"
}

variable "use_tag_based_targeting" {
  description = "trueの場合タグベースでSSM対象を指定、falseの場合ec2モジュールが作成したインスタンスIDを直接指定する"
  type        = bool
  default     = false
}

variable "default_app_config_name" {
  description = "Launcherが起動時に参照するデフォルトのアプリケーション設定名"
  type        = string
  default     = "sample-uppercase"
}

variable "launcher_script_s3_key" {
  description = "launcher.ps1のS3キー(scriptsバケット配下)"
  type        = string
  default     = "launcher/launcher.ps1"
}

variable "lambda_timeout_seconds" {
  description = "Job Dispatcher LambdaのTimeout秒数"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Job Dispatcher LambdaのMemorySize(MB)"
  type        = number
  default     = 256
}

variable "lambda_reserved_concurrency" {
  description = "Job Dispatcher Lambdaの予約済み同時実行数(-1で未設定)"
  type        = number
  default     = -1
}

variable "ssm_command_timeout_seconds" {
  description = "Launcher実行(SSM Run Command)のタイムアウト秒数"
  type        = number
  default     = 7200
}

variable "step_functions_poll_interval_seconds" {
  description = "Step Functions利用時のSSMコマンド完了ポーリング間隔(秒)"
  type        = number
  default     = 30
}

variable "step_functions_max_poll_attempts" {
  description = "Step Functions利用時のSSMコマンド完了ポーリング最大回数(実効タイムアウト = 間隔×回数)"
  type        = number
  default     = 240
}
