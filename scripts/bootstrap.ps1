# ==================================================================
# bootstrap.ps1 (サンプル/プレースホルダー)
# ==================================================================
# このスクリプトはTerraformが管理する範囲外です。
# 実際のアプリケーションインストール・ランタイムセットアップ(Python/PowerShellモジュール/
# .NET/Visual C++ Runtime/Anaconda等)は、運用チームがこのファイルの内容を
# 実装して置き換えてください。
#
# Terraformは以下のいずれかの方法でこのスクリプトを実行できる状態まで用意します。
#   1. setup_script_execution_mode = "userdata"       : EC2起動時にUserDataから自動実行
#   2. setup_script_execution_mode = "ssm_run_command" : 任意タイミングで
#        aws ssm send-command --document-name <name>-run-setup-script を実行
#   3. setup_script_execution_mode = "state_manager"   : SSM Associationにより
#        起動時に自動適用(定期実行にも拡張可能)
#
# 配置先: S3 scriptsバケット / setup_script_s3_key で指定したキー
# ==================================================================

$ErrorActionPreference = "Stop"
$logDir = "C:\PSLogs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
Start-Transcript -Path (Join-Path $logDir "bootstrap.log") -Append

try {
    Write-Host "=== bootstrap.ps1 開始 ==="

    # 例: FSx共有フォルダのドライブマッピング(実運用に合わせて調整すること)
    # $fsxDnsName = $env:APP_FSX_DNS_NAME
    # if ($fsxDnsName) {
    #     New-PSDrive -Name "Z" -PSProvider FileSystem -Root "\\$fsxDnsName\Input" -Persist
    # }

    # 例: アプリケーションランタイムのインストール(Chocolatey/MSI/カスタムインストーラ等)
    # 例: Pythonインストール
    # 例: 対象アプリケーションのインストール・設定

    Write-Host "=== bootstrap.ps1 正常終了(プレースホルダーのため実処理は未実装) ==="
}
catch {
    Write-Error "bootstrap.ps1でエラーが発生しました: $_"
    throw
}
finally {
    Stop-Transcript
}
