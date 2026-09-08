#Requires -Version 5.1
<#
.SYNOPSIS
    サンプルWindowsアプリケーション: 入力テキストを大文字変換して出力する。

.DESCRIPTION
    tf-winイベント駆動ジョブ実行基盤の動作確認用サンプルアプリです。
    Launcherとのインターフェース(--input/--output相当)を実際のWindowsアプリと
    同様の形で実装しており、本アプリを実行ファイル(HFSS/CAD/CAE/独自EXE等)へ
    差し替えるだけで任意のアプリケーションへ対応できることを示します。

.PARAMETER InputPath
    入力ファイルパス(例: sample.txt に "hello world" を含む)。

.PARAMETER OutputPath
    出力ファイルパス。入力内容を大文字変換した結果を書き込む。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InputPath)) {
    Write-Error "入力ファイルが見つかりません: $InputPath"
    exit 1
}

$content = Get-Content -Path $InputPath -Raw -Encoding utf8
$upper = $content.ToUpperInvariant()

$outputDir = Split-Path -Parent $OutputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

Set-Content -Path $OutputPath -Value $upper -Encoding utf8 -NoNewline

Write-Host "Converted '$InputPath' to uppercase -> '$OutputPath'"
exit 0
