# Step Functions によるジョブオーケストレーション (オプション)
#
# EventBridge -> Step Functions -> Lambda(ジョブ投入) -> SSM GetCommandInvocation(ポーリング) -> 結果判定
#
# 単純にEventBridge -> Lambda -> SSM で完結させる方式と比較したメリット・デメリットは
# README.md「Step Functions採用の是非」を参照。

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name               = "${var.name_prefix}-job-orchestration-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-job-orchestration-role"
  })
}

data "aws_iam_policy_document" "state_machine_permissions" {
  statement {
    sid       = "InvokeJobDispatcherLambda"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [var.lambda_function_arn]
  }

  statement {
    sid    = "SSMCommandStatusCheck"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
    ]
    resources = ["*"] # GetCommandInvocationはリソースレベル権限未対応のため*を許容
  }

  statement {
    sid    = "CloudWatchLogsDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"] # Step Functionsのロギング連携要件によりワイルドカードが必要(AWS公式ドキュメント準拠)
  }
}

resource "aws_iam_policy" "state_machine_permissions" {
  name   = "${var.name_prefix}-job-orchestration-policy"
  policy = data.aws_iam_policy_document.state_machine_permissions.json
}

resource "aws_iam_role_policy_attachment" "state_machine_permissions" {
  role       = aws_iam_role.state_machine.name
  policy_arn = aws_iam_policy.state_machine_permissions.arn
}

##############################
# EventBridgeがこのステートマシンを起動するためのIAMロール
##############################

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_invoke" {
  name               = "${var.name_prefix}-eventbridge-invoke-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eventbridge-invoke-sfn-role"
  })
}

data "aws_iam_policy_document" "eventbridge_invoke_permissions" {
  statement {
    sid       = "StartStateMachineExecution"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.job_orchestration.arn]
  }
}

resource "aws_iam_policy" "eventbridge_invoke_permissions" {
  name   = "${var.name_prefix}-eventbridge-invoke-sfn-policy"
  policy = data.aws_iam_policy_document.eventbridge_invoke_permissions.json
}

resource "aws_iam_role_policy_attachment" "eventbridge_invoke_permissions" {
  role       = aws_iam_role.eventbridge_invoke.name
  policy_arn = aws_iam_policy.eventbridge_invoke_permissions.arn
}

##############################
# State Machine定義
##############################
# フロー:
#   1. DispatchJob        : Lambdaを呼び出しSSM SendCommandでLauncherを起動
#   2. WaitForCompletion  : ポーリング間隔だけ待機
#   3. CheckCommandStatus : SSM GetCommandInvocationで実行状況を確認
#   4. 分岐:
#      - Success   -> JobSucceeded (正常終了)
#      - Failed/Cancelled/TimedOut -> JobFailed (異常終了、CloudWatch Logsへ記録)
#      - InProgress/Pending -> WaitForCompletionへ戻る(タイムアウトまで繰り返す)

resource "aws_sfn_state_machine" "job_orchestration" {
  name     = "${var.name_prefix}-job-orchestration"
  role_arn = aws_iam_role.state_machine.arn

  logging_configuration {
    log_destination        = "${var.log_group_arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "Windowsアプリケーションジョブのオーケストレーション(投入 -> ポーリング -> 結果判定)"
    StartAt = "DispatchJob"
    States = {
      DispatchJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = var.lambda_function_arn
          "Payload.$"    = "$"
        }
        ResultSelector = {
          "jobId.$"       = "$.Payload.jobId"
          "commandId.$"   = "$.Payload.commandId"
          "inputBucket.$" = "$.Payload.inputBucket"
          "inputKey.$"    = "$.Payload.inputKey"
        }
        ResultPath = "$.dispatch"
        Retry = [
          {
            ErrorEquals     = ["Lambda.TooManyRequestsException", "Lambda.ServiceException"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "JobFailed"
          }
        ]
        Next = "InitPollCount"
      }

      InitPollCount = {
        Type       = "Pass"
        Result     = { count = 0 }
        ResultPath = "$.poll"
        Next       = "WaitForCompletion"
      }

      WaitForCompletion = {
        Type    = "Wait"
        Seconds = var.poll_interval_seconds
        Next    = "CheckCommandStatus"
      }

      CheckCommandStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ssm:getCommandInvocation"
        Parameters = {
          "CommandId.$"  = "$.dispatch.commandId"
          "InstanceId.$" = "$.dispatch.instanceId"
        }
        ResultPath = "$.status"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "JobFailed"
          }
        ]
        Next = "EvaluateStatus"
      }

      EvaluateStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.status.Status"
            StringEquals = "Success"
            Next         = "JobSucceeded"
          },
          {
            Variable     = "$.status.Status"
            StringEquals = "Failed"
            Next         = "JobFailed"
          },
          {
            Variable     = "$.status.Status"
            StringEquals = "Cancelled"
            Next         = "JobFailed"
          },
          {
            Variable     = "$.status.Status"
            StringEquals = "TimedOut"
            Next         = "JobFailed"
          }
        ]
        Default = "IncrementPollCount"
      }

      IncrementPollCount = {
        Type = "Pass"
        Parameters = {
          "count.$" = "States.MathAdd($.poll.count, 1)"
        }
        ResultPath = "$.poll"
        Next       = "CheckPollLimit"
      }

      CheckPollLimit = {
        Type = "Choice"
        Choices = [
          {
            Variable                 = "$.poll.count"
            NumericGreaterThanEquals = var.max_poll_attempts
            Next                     = "JobTimedOut"
          }
        ]
        Default = "WaitForCompletion"
      }

      JobSucceeded = {
        Type = "Succeed"
      }

      JobFailed = {
        Type  = "Fail"
        Error = "JobExecutionFailed"
        Cause = "SSM Run Commandによるジョブ実行が失敗しました"
      }

      JobTimedOut = {
        Type  = "Fail"
        Error = "JobExecutionTimedOut"
        Cause = "ジョブ実行がタイムアウトしました(max_poll_attempts到達)"
      }
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-job-orchestration"
  })
}
