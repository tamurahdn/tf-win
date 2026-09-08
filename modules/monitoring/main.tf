##############################
# SNS通知(オプション)
##############################

resource "aws_sns_topic" "alarms" {
  count             = var.enable_sns_notifications ? 1 : 0
  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alarms"
  })
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.enable_sns_notifications && var.sns_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

locals {
  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.alarms[0].arn] : []
}

##############################
# CPU使用率
##############################

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each            = toset(var.instance_ids)
  alarm_name          = "${var.name_prefix}-cpu-high-${each.value}"
  alarm_description   = "EC2 CPU使用率が閾値を超過"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.alarm_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = var.tags
}

##############################
# メモリ使用率(CloudWatch Agentが送信するカスタムメトリクス)
##############################

resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each            = toset(var.instance_ids)
  alarm_name          = "${var.name_prefix}-memory-high-${each.value}"
  alarm_description   = "EC2メモリ使用率が閾値を超過(CloudWatch Agent必須)"
  namespace           = "CWAgent"
  metric_name         = "Memory % Committed Bytes In Use"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.alarm_memory_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = var.tags
}

##############################
# ディスク使用率(CloudWatch Agentが送信するカスタムメトリクス、Cドライブ想定)
##############################

resource "aws_cloudwatch_metric_alarm" "disk" {
  for_each            = toset(var.instance_ids)
  alarm_name          = "${var.name_prefix}-disk-high-${each.value}"
  alarm_description   = "EC2ディスク使用率が閾値を超過(CloudWatch Agent必須)"
  namespace           = "CWAgent"
  metric_name         = "LogicalDisk % Free Space"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 100 - var.alarm_disk_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = each.value
    instance   = "C:"
    objectname = "LogicalDisk"
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = var.tags
}

##############################
# ステータスチェック失敗
##############################

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  for_each            = toset(var.instance_ids)
  alarm_name          = "${var.name_prefix}-status-check-failed-${each.value}"
  alarm_description   = "EC2ステータスチェックが失敗"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = var.tags
}

##############################
# EC2停止検知(InstanceStateChangeイベントを想定しStatusCheckFailed_Systemで代替)
##############################
# 「停止」自体を検知する場合はEventBridge Rule(EC2 Instance State-change Notification)
# を利用する方がより正確なため、そちらもあわせて構築する。

resource "aws_cloudwatch_event_rule" "instance_stopped" {
  name        = "${var.name_prefix}-instance-stopped"
  description = "EC2インスタンス停止を検知する"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state      = ["stopped"]
      instance-id = var.instance_ids
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_stopped_sns" {
  count     = var.enable_sns_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.instance_stopped.name
  target_id = "sns"
  arn       = aws_sns_topic.alarms[0].arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  count = var.enable_sns_notifications ? 1 : 0
  arn   = aws_sns_topic.alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms[0].arn
      }
    ]
  })
}

##############################
# SSM Agent疎通異常(Ping Statusをコンプライアンスで検知)
##############################
# CloudWatch標準メトリクスには直接的なSSM Agent死活監視指標がないため、
# EventBridgeでSSM Compliance変化を捕捉するルールを用意する。

resource "aws_cloudwatch_event_rule" "ssm_compliance_change" {
  name        = "${var.name_prefix}-ssm-compliance-change"
  description = "SSM Agentのコンプライアンス状態変化(異常)を検知する"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Configuration Compliance State Change"]
    detail = {
      compliance-status = ["NON_COMPLIANT"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "ssm_compliance_change_sns" {
  count     = var.enable_sns_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.ssm_compliance_change.name
  target_id = "sns"
  arn       = aws_sns_topic.alarms[0].arn
}

##############################
# FSxストレージ容量
##############################

resource "aws_cloudwatch_metric_alarm" "fsx_storage_capacity" {
  alarm_name          = "${var.name_prefix}-fsx-storage-low"
  alarm_description   = "FSx空き容量が閾値を下回った(目安: 総容量の10%未満)"
  namespace           = "AWS/FSx"
  metric_name         = "FreeStorageCapacity"
  statistic           = "Average"
  period              = 300
  evaluation_periods   = 3
  threshold           = 10 * 1024 * 1024 * 1024 # 10GiB(必要に応じて環境ごとに調整)
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    FileSystemId = var.fsx_file_system_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = var.tags
}
