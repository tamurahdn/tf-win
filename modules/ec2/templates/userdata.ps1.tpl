<powershell>
# ==================================================================
# UserData: インスタンス起動時の最小限初期化処理
# ここではCloudWatch Agentの導入・設定適用と、
# setup_script_execution_mode=userdata の場合のみ初期セットアップスクリプトの取得・実行を行う。
# Python/PowerShell/.NET等のランタイムやアプリケーション自体のインストールは
# セットアップスクリプト側の責務であり、本UserDataでは実施しない。
# ==================================================================

$ErrorActionPreference = "Stop"
$logFile = "C:\ProgramData\Amazon\setup-userdata.log"
Start-Transcript -Path $logFile -Append

try {
    Write-Host "=== CloudWatch Agent セットアップ開始 ==="

    $cwaInstallerUrl = "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi"
    $cwaInstallerPath = "C:\ProgramData\Amazon\amazon-cloudwatch-agent.msi"
    Invoke-WebRequest -Uri $cwaInstallerUrl -OutFile $cwaInstallerPath
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$cwaInstallerPath`" /qn" -Wait

    # CloudWatch Agent設定はSSMパラメータストアから取得し適用する(設定内容はハードコードしない)
    $cwaCtlPath = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"
    if (Test-Path $cwaCtlPath) {
        & $cwaCtlPath -a fetch-config -m ec2 -c "ssm:${cloudwatch_agent_config_ssm_param_name}" -s
    }

    Write-Host "=== CloudWatch Agent セットアップ完了 ==="

    # FSx共有先をアプリ用環境変数として設定(セットアップスクリプトから参照可能にする)
    %{ if fsx_dns_name != "" }
    [System.Environment]::SetEnvironmentVariable("APP_FSX_DNS_NAME", "${fsx_dns_name}", "Machine")
    %{ endif }

    %{ if execution_mode == "userdata" }
    Write-Host "=== 初期セットアップスクリプト取得・実行開始 (mode=userdata) ==="
    $scriptLocalPath = Join-Path $env:TEMP (Split-Path -Leaf "${setup_script_s3_key}")
    Read-S3Object -BucketName "${scripts_bucket_name}" -Key "${setup_script_s3_key}" -File $scriptLocalPath
    Write-Host "Executing $scriptLocalPath"
    & $scriptLocalPath
    Write-Host "=== 初期セットアップスクリプト実行完了 ==="
    %{ else }
    Write-Host "=== execution_mode=${execution_mode} のためUserDataでのスクリプト実行はスキップします ==="
    Write-Host "SSM Run Command / State Manager経由で別途実行してください"
    %{ endif }

    Write-Host "=== UserData処理正常終了 ==="
}
catch {
    Write-Error "UserData処理でエラーが発生しました: $_"
    throw
}
finally {
    Stop-Transcript
}
</powershell>
