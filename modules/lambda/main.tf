# Job Dispatcher Lambda
#
# 責務: S3イベント受信 → ジョブID生成 → SSM Run Command実行 → ログ出力 → エラーハンドリング
# Windowsアプリケーションの詳細(実行ファイル・引数体系)には一切関与しない疎結合設計とする。

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  function_name = "${var.name_prefix}-job-dispatcher"
}

##############################
# Lambdaコード(archiveプロバイダでZIP化)
##############################

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/job-dispatcher.zip"
}

##############################
# IAMロール(最小権限: SSM SendCommand + CloudWatch Logs書き込みのみ)
##############################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Name = "${local.function_name}-role"
  })
}

# SSM SendCommandは対象ドキュメント・対象インスタンスのARNに限定する(最小権限)。
# タグベースターゲットを利用する場合はinstance/*に限定した上でCondition等の追加を検討すること。
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "SSMSendCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = compact([
      "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunPowerShellScript",
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:document/${var.ssm_document_name}",
    ])
  }

  statement {
    sid    = "SSMSendCommandTargetInstances"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = length(var.target_instance_ids) > 0 ? [
      for id in var.target_instance_ids :
      "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/${id}"
      ] : [
      "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
  }

  statement {
    sid    = "SSMCommandStatus"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"] # これらのRead系APIはリソースレベル権限をサポートしないため*を許容する
  }

  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*",
    ]
  }

  statement {
    sid    = "KMSUsage"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_policy" "lambda_permissions" {
  name   = "${local.function_name}-policy"
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_permissions" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}

##############################
# CloudWatch Logs (Lambda用ロググループを明示管理し保持期間・KMSを制御)
##############################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${local.function_name}-logs"
  })
}

##############################
# Lambda Function
##############################

resource "aws_lambda_function" "job_dispatcher" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      SSM_DOCUMENT_NAME       = var.ssm_document_name
      TARGET_INSTANCE_IDS     = join(",", var.target_instance_ids)
      TARGET_TAG_KEY          = var.target_tag_key
      TARGET_TAG_VALUE        = var.target_tag_value
      OUTPUT_BUCKET           = var.output_bucket_name
      LOGS_BUCKET             = var.logs_bucket_name
      FSX_WORKSPACE_SHARE     = var.fsx_workspace_share
      APP_CONFIG_NAME         = var.app_config_name
      COMMAND_TIMEOUT_SECONDS = tostring(var.command_timeout_seconds)
      LOG_LEVEL               = "INFO"
    }
  }

  tracing_config {
    mode = "Active" # X-Rayトレースを有効化しジョブ投入の遅延・失敗箇所を追跡可能にする
  }

  tags = merge(var.tags, {
    Name = local.function_name
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_permissions,
  ]
}
