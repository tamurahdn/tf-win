"""
Job Dispatcher Lambda
======================
S3 Inputバケットへのオブジェクト作成イベント(EventBridge経由)を受信し、
Windows EC2上でLauncherを起動するためのSSM Run Commandを発行する。

本Lambdaの責務は以下のみとする(要件定義に準拠):
  - S3イベント受信
  - アップロードファイル取得(バケット名・キーの抽出)
  - ジョブID生成
  - SSM Run Command実行
  - CloudWatch Logs出力
  - エラーハンドリング

Windowsアプリケーション自体の詳細(実行ファイル名・引数体系・処理内容)には
一切関与しない。Launcher側とのインターフェースは
「input/output/workdir/jobid」という共通パラメータのみに限定される。
"""

import json
import logging
import os
import time
import urllib.parse
import uuid
from typing import Any, Dict

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# リトライ設定を明示し、SSM/CloudWatchへの一時的なスロットリングに対応する
_boto_config = Config(retries={"max_attempts": 3, "mode": "standard"})

ssm_client = boto3.client("ssm", config=_boto_config)

# Lambda実行環境間で使い回すための環境変数(Terraformから注入)
SSM_DOCUMENT_NAME = os.environ["SSM_DOCUMENT_NAME"]
TARGET_INSTANCE_IDS = [
    i for i in os.environ.get("TARGET_INSTANCE_IDS", "").split(",") if i
]
TARGET_TAG_KEY = os.environ.get("TARGET_TAG_KEY", "")
TARGET_TAG_VALUE = os.environ.get("TARGET_TAG_VALUE", "")
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
LOGS_BUCKET = os.environ["LOGS_BUCKET"]
FSX_WORKSPACE_SHARE = os.environ.get("FSX_WORKSPACE_SHARE", "")
COMMAND_TIMEOUT_SECONDS = int(os.environ.get("COMMAND_TIMEOUT_SECONDS", "3600"))
APP_CONFIG_NAME = os.environ.get("APP_CONFIG_NAME", "sample-uppercase")


class JobDispatchError(Exception):
    """ジョブ投入処理内で発生した回復不能なエラーを表す。"""


def _extract_s3_event(record: Dict[str, Any]) -> Dict[str, str]:
    """EventBridge経由のS3 ObjectCreatedイベントからバケット名・キーを抽出する。

    EventBridge(S3イベント通知)のdetailは以下の形式を取る:
      {
        "version": "0",
        "detail-type": "Object Created",
        "source": "aws.s3",
        "detail": {
          "bucket": {"name": "..."},
          "object": {"key": "...", "size": ..., "etag": "..."}
        }
      }
    """
    detail = record.get("detail", {})
    bucket = detail.get("bucket", {}).get("name")
    key = detail.get("object", {}).get("key")

    if not bucket or not key:
        raise JobDispatchError(f"S3イベントの解析に失敗しました: detail={detail}")

    # S3キーはURLエンコードされている場合があるためデコードする
    key = urllib.parse.unquote_plus(key)
    return {"bucket": bucket, "key": key}


def _generate_job_id() -> str:
    """一意なジョブIDを生成する。時刻プレフィックス+UUIDで人間にも追跡しやすくする。"""
    timestamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    return f"{timestamp}-{uuid.uuid4().hex[:8]}"


def _build_ssm_parameters(job_id: str, input_bucket: str, input_key: str) -> Dict[str, list]:
    """SSMドキュメントへ渡すパラメータを構築する。

    Launcher(launcher.ps1)とのインターフェースは以下の共通パラメータのみ。
    アプリケーション固有の引数はLauncher内のconfigファイル経由で解決するため、
    Lambdaはアプリケーションの詳細を一切知る必要がない。
    """
    return {
        "jobId": [job_id],
        "inputBucket": [input_bucket],
        "inputKey": [input_key],
        "outputBucket": [OUTPUT_BUCKET],
        "logsBucket": [LOGS_BUCKET],
        "appConfigName": [APP_CONFIG_NAME],
    }


def _send_command(job_id: str, parameters: Dict[str, list]) -> Dict[str, str]:
    """SSM Run Commandを発行し、CommandIdと対象InstanceIdを返す。

    Step Functions経由でジョブ状態をポーリングする場合、
    ssm:GetCommandInvocation にはCommandIdに加えInstanceIdが必須となるため、
    単一ターゲット運用を前提に先頭のインスタンスIDを採用する。
    複数台のWorkerへ同時ディスパッチする構成へ拡張する場合は、
    ジョブごとにターゲットを1台へ限定するキューイング層(SQS等)の追加を推奨する。
    """
    kwargs: Dict[str, Any] = {
        "DocumentName": SSM_DOCUMENT_NAME,
        "Parameters": parameters,
        "TimeoutSeconds": COMMAND_TIMEOUT_SECONDS,
        "Comment": f"tf-win job dispatch: {job_id}",
        "CloudWatchOutputConfig": {
            "CloudWatchOutputEnabled": True,
        },
    }

    if TARGET_INSTANCE_IDS:
        kwargs["InstanceIds"] = TARGET_INSTANCE_IDS
    elif TARGET_TAG_KEY and TARGET_TAG_VALUE:
        kwargs["Targets"] = [{"Key": f"tag:{TARGET_TAG_KEY}", "Values": [TARGET_TAG_VALUE]}]
    else:
        raise JobDispatchError(
            "SSM Run Commandの実行対象が指定されていません"
            "(TARGET_INSTANCE_IDS または TARGET_TAG_KEY/TARGET_TAG_VALUE が必要)"
        )

    try:
        response = ssm_client.send_command(**kwargs)
    except ClientError as exc:
        # SSM側の障害・スロットリング・EC2オフライン等はここで捕捉しCloudWatch Logsへ記録する
        logger.error(
            json.dumps(
                {
                    "event": "ssm_send_command_failed",
                    "job_id": job_id,
                    "error": str(exc),
                }
            )
        )
        raise JobDispatchError(f"SSM SendCommandに失敗しました: {exc}") from exc

    command = response["Command"]
    command_id = command["CommandId"]

    instance_ids = command.get("InstanceIds", [])
    if not instance_ids:
        # タグターゲットの場合、SendCommand応答直後は対象解決が非同期のため
        # ListCommandInvocationsで実際の対象インスタンスを取得する
        instance_ids = _resolve_target_instance_ids(command_id)

    if not instance_ids:
        raise JobDispatchError(
            f"SSMコマンド({command_id})の対象インスタンスを特定できませんでした"
        )

    return {"command_id": command_id, "instance_id": instance_ids[0]}


def _resolve_target_instance_ids(command_id: str, max_attempts: int = 5) -> list:
    """タグベースターゲット利用時、SendCommand直後は対象解決が非同期のため
    ListCommandInvocationsで実際の対象インスタンスIDが確定するまで短時間リトライする。
    """
    for attempt in range(max_attempts):
        try:
            response = ssm_client.list_command_invocations(CommandId=command_id)
        except ClientError as exc:
            logger.warning(
                json.dumps(
                    {
                        "event": "list_command_invocations_failed",
                        "command_id": command_id,
                        "attempt": attempt,
                        "error": str(exc),
                    }
                )
            )
            time.sleep(1)
            continue

        invocations = response.get("CommandInvocations", [])
        if invocations:
            return [inv["InstanceId"] for inv in invocations]
        time.sleep(1)

    return []


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Lambdaエントリポイント。

    EventBridge経由でS3 ObjectCreatedイベントを受け取り、
    ジョブIDを発行してSSM Run Commandでlauncher.ps1を起動する。
    """
    logger.info(json.dumps({"event": "lambda_invoked", "raw_event": event}))

    try:
        s3_info = _extract_s3_event(event)
    except JobDispatchError as exc:
        logger.error(json.dumps({"event": "invalid_s3_event", "error": str(exc)}))
        # 入力イベント自体が不正な場合はリトライしても解決しないため、そのまま終了する
        raise

    job_id = _generate_job_id()

    logger.info(
        json.dumps(
            {
                "event": "job_created",
                "job_id": job_id,
                "input_bucket": s3_info["bucket"],
                "input_key": s3_info["key"],
            }
        )
    )

    parameters = _build_ssm_parameters(job_id, s3_info["bucket"], s3_info["key"])

    try:
        dispatch_result = _send_command(job_id, parameters)
    except JobDispatchError as exc:
        logger.error(
            json.dumps({"event": "job_dispatch_failed", "job_id": job_id, "error": str(exc)})
        )
        raise

    logger.info(
        json.dumps(
            {
                "event": "job_dispatched",
                "job_id": job_id,
                "command_id": dispatch_result["command_id"],
                "instance_id": dispatch_result["instance_id"],
                "input_bucket": s3_info["bucket"],
                "input_key": s3_info["key"],
            }
        )
    )

    return {
        "jobId": job_id,
        "commandId": dispatch_result["command_id"],
        "instanceId": dispatch_result["instance_id"],
        "inputBucket": s3_info["bucket"],
        "inputKey": s3_info["key"],
    }
