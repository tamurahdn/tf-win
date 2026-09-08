#Requires -Version 5.1
<#
.SYNOPSIS
    tf-win イベント駆動ジョブ実行基盤 共通Launcher

.DESCRIPTION
    本スクリプトはAWSサービス(Lambda/SSM)とWindowsアプリケーションを疎結合に保つための
    汎用ランチャーです。以下の責務のみを担い、対象アプリケーションの詳細には関与しません。

      1. 入力ファイルをS3からFSx上のジョブ作業ディレクトリへ取得
      2. 作業ディレクトリ(Workspace/{JobId})の作成
      3. アプリケーション設定(AppConfigName)に応じたコマンドの起動
      4. 終了コードの取得
      5. ログ出力(ローカル・S3・CloudWatch Logs[SSM経由])
      6. 出力ファイルのS3アップロード
      7. 終了通知(構造化ログとしてSTDOUTへ出力。SSM実行結果はCloudWatch Logsへ自動転送される)

    対象アプリケーションを差し替える場合は、本スクリプトを変更するのではなく
    config/ 配下のアプリケーション設定(JSON)を追加/変更してください。

.PARAMETER JobId
    ジョブの一意識別子。Workspace配下のサブディレクトリ名として使用する。

.PARAMETER InputBucket
    入力ファイルが格納されているS3バケット名。

.PARAMETER InputKey
    入力ファイルのS3キー。

.PARAMETER OutputBucket
    出力ファイルを格納するS3バケット名。

.PARAMETER LogsBucket
    ログを格納するS3バケット名。

.PARAMETER AppConfigName
    起動対象アプリケーションの設定名。config/{AppConfigName}.json を読み込む。

.PARAMETER FsxRoot
    FSxで公開されている共有フォルダのルートパス(ドライブレターまたはUNCパス)。

.PARAMETER ConfigRoot
    アプリケーション設定(JSON)が格納されたディレクトリ。既定はスクリプト自身と同階層の config。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$JobId,
    [Parameter(Mandatory = $true)][string]$InputBucket,
    [Parameter(Mandatory = $true)][string]$InputKey,
    [Parameter(Mandatory = $true)][string]$OutputBucket,
    [Parameter(Mandatory = $true)][string]$LogsBucket,
    [Parameter(Mandatory = $true)][string]$AppConfigName,
    [string]$FsxRoot = "Z:\Workspace",
    [string]$ConfigRoot = (Join-Path $PSScriptRoot "config")
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# ログ出力ヘルパー
# 構造化(JSON)ログをSTDOUTへ出力する。SSM Run CommandのCloudWatchOutputEnabled
# 設定により、この標準出力は自動的にCloudWatch Logsへ転送される。
# ---------------------------------------------------------------------------
function Write-JobLog {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Status = "INFO",
        [hashtable]$Extra = @{}
    )

    $entry = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        jobId     = $JobId
        event     = $Event
        status    = $Status
    }
    foreach ($key in $Extra.Keys) {
        $entry[$key] = $Extra[$key]
    }

    $json = $entry | ConvertTo-Json -Compress
    Write-Output $json
    Add-Content -Path $script:LocalLogFile -Value $json -Encoding utf8
}

function Complete-Job {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Message = "",
        [int]$ExitCode = 0
    )

    Write-JobLog -Event "job_completed" -Status $Status -Extra @{
        message  = $Message
        exitCode = $ExitCode
    }

    # ローカルログをLogsバケットへアップロード(失敗してもジョブ自体の成否には影響させない)
    try {
        if (Test-Path $script:LocalLogFile) {
            $logKey = "job-logs/$JobId/launcher.log"
            Write-S3Object -BucketName $LogsBucket -File $script:LocalLogFile -Key $logKey | Out-Null
        }
    }
    catch {
        Write-Output (@{ event = "log_upload_failed"; jobId = $JobId; error = $_.Exception.Message } | ConvertTo-Json -Compress)
    }

    exit $ExitCode
}

# ---------------------------------------------------------------------------
# 作業ディレクトリ準備
# ---------------------------------------------------------------------------
$workDir = Join-Path $FsxRoot $JobId
$inputDir = Join-Path $workDir "input"
$outputDir = Join-Path $workDir "output"
$tempDir = Join-Path $workDir "temp"

New-Item -ItemType Directory -Force -Path $workDir, $inputDir, $outputDir, $tempDir | Out-Null

$script:LocalLogFile = Join-Path $tempDir "launcher.log"
New-Item -ItemType File -Force -Path $script:LocalLogFile | Out-Null

Write-JobLog -Event "job_started" -Extra @{
    inputBucket   = $InputBucket
    inputKey      = $InputKey
    outputBucket  = $OutputBucket
    appConfigName = $AppConfigName
    workDir       = $workDir
}

# ---------------------------------------------------------------------------
# アプリケーション設定の読み込み
# 設定ファイルはアプリケーションごとに config/{AppConfigName}.json として用意する。
# 例: { "executable": "C:\\Apps\\App.exe", "arguments": ["--input","{input}","--output","{output}","--workdir","{workdir}"] }
# ---------------------------------------------------------------------------
$configPath = Join-Path $ConfigRoot "$AppConfigName.json"
if (-not (Test-Path $configPath)) {
    Write-JobLog -Event "app_config_not_found" -Status "FAILED" -Extra @{ configPath = $configPath }
    Complete-Job -Status "FAILED" -Message "アプリケーション設定が見つかりません: $configPath" -ExitCode 10
}

try {
    $appConfig = Get-Content -Path $configPath -Raw -Encoding utf8 | ConvertFrom-Json
}
catch {
    Write-JobLog -Event "app_config_parse_error" -Status "FAILED" -Extra @{ error = $_.Exception.Message }
    Complete-Job -Status "FAILED" -Message "アプリケーション設定の解析に失敗しました" -ExitCode 11
}

# ---------------------------------------------------------------------------
# 入力ファイル取得
# ---------------------------------------------------------------------------
$inputFileName = Split-Path -Leaf $InputKey
$localInputPath = Join-Path $inputDir $inputFileName

try {
    Read-S3Object -BucketName $InputBucket -Key $InputKey -File $localInputPath | Out-Null
}
catch {
    Write-JobLog -Event "input_fetch_failed" -Status "FAILED" -Extra @{ error = $_.Exception.Message }
    Complete-Job -Status "FAILED" -Message "入力ファイルの取得に失敗しました(不存在の可能性): $InputKey" -ExitCode 20
}

if (-not (Test-Path $localInputPath)) {
    Write-JobLog -Event "input_file_missing" -Status "FAILED"
    Complete-Job -Status "FAILED" -Message "入力ファイルが存在しません: $localInputPath" -ExitCode 21
}

Write-JobLog -Event "input_fetched" -Extra @{ localInputPath = $localInputPath }

# ---------------------------------------------------------------------------
# アプリケーション起動
# 設定内のプレースホルダ {input}/{output}/{workdir}/{config} を実値へ置換する。
# ---------------------------------------------------------------------------
$outputFileName = if ($appConfig.outputFileName) { $appConfig.outputFileName } else { $inputFileName }
$localOutputPath = Join-Path $outputDir $outputFileName

$placeholders = @{
    "{input}"   = $localInputPath
    "{output}"  = $localOutputPath
    "{workdir}" = $workDir
    "{config}"  = $configPath
}

$resolvedArgs = @()
foreach ($arg in $appConfig.arguments) {
    $resolved = $arg
    foreach ($key in $placeholders.Keys) {
        $resolved = $resolved -replace [regex]::Escape($key), [regex]::Escape($placeholders[$key]).Replace('\', '\\')
        $resolved = $resolved.Replace($key, $placeholders[$key])
    }
    $resolvedArgs += $resolved
}

Write-JobLog -Event "app_launch" -Extra @{
    executable = $appConfig.executable
    arguments  = ($resolvedArgs -join " ")
}

$exitCode = -1
try {
    $process = Start-Process -FilePath $appConfig.executable -ArgumentList $resolvedArgs `
        -WorkingDirectory $workDir -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $tempDir "app_stdout.log") `
        -RedirectStandardError (Join-Path $tempDir "app_stderr.log")
    $exitCode = $process.ExitCode
}
catch {
    Write-JobLog -Event "app_launch_error" -Status "FAILED" -Extra @{ error = $_.Exception.Message }
    Complete-Job -Status "FAILED" -Message "アプリケーションの起動に失敗しました" -ExitCode 30
}

Write-JobLog -Event "app_exited" -Extra @{ exitCode = $exitCode }

if ($exitCode -ne 0) {
    Write-JobLog -Event "app_abnormal_exit" -Status "FAILED" -Extra @{ exitCode = $exitCode }
    Complete-Job -Status "FAILED" -Message "アプリケーションが異常終了しました(ExitCode=$exitCode)" -ExitCode $exitCode
}

# ---------------------------------------------------------------------------
# 出力ファイル確認・アップロード
# ---------------------------------------------------------------------------
if (-not (Test-Path $localOutputPath)) {
    Write-JobLog -Event "output_file_missing" -Status "FAILED" -Extra @{ localOutputPath = $localOutputPath }
    Complete-Job -Status "FAILED" -Message "出力ファイルが生成されませんでした: $localOutputPath" -ExitCode 40
}

$outputKey = "$JobId/$outputFileName"
try {
    Write-S3Object -BucketName $OutputBucket -File $localOutputPath -Key $outputKey | Out-Null
}
catch {
    Write-JobLog -Event "output_upload_failed" -Status "FAILED" -Extra @{ error = $_.Exception.Message }
    Complete-Job -Status "FAILED" -Message "出力ファイルのアップロードに失敗しました" -ExitCode 41
}

Write-JobLog -Event "output_uploaded" -Extra @{ outputBucket = $OutputBucket; outputKey = $outputKey }

Complete-Job -Status "SUCCEEDED" -Message "ジョブが正常に完了しました" -ExitCode 0
