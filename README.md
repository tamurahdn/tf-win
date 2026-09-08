# tf-win: Windowsデスクトップアプリケーション実行基盤 (Terraform)

Windows上で動作するデスクトップアプリケーション(CAD/CAE/解析ソフト/RPA対象アプリ/
社内業務アプリ等)をAWS上で実行するための基盤をTerraformで構築するプロジェクトです。

**本Terraformの責務はインフラ構築までです。** 対象アプリケーションのインストールや
Python・PowerShell・.NET・Visual C++ Runtime・Anacondaなどの実行環境構築は、
[scripts/](./scripts) に配置する初期セットアップスクリプト(PowerShell等)で別途行います。

---

## 目次

1. [システム概要](#システム概要)
2. [イベント駆動ジョブ実行基盤](#イベント駆動ジョブ実行基盤)
3. [前提ソフトウェア](#前提ソフトウェア)
4. [AWS認証情報の設定方法](#aws認証情報の設定方法)
5. [Terraform実行方法](#terraform実行方法)
6. [トラブルシューティング](#トラブルシューティング)
7. [設計判断理由 / 採用しなかった構成案](#設計判断理由--採用しなかった構成案)
8. [将来拡張](#将来拡張)

---

## システム概要

### アーキテクチャ図

```mermaid
flowchart TB
    subgraph Internet
        Admin[運用担当者<br/>Session Manager / RDP]
    end

    subgraph AWS["AWSアカウント"]
        subgraph VPC["VPC (10.0.0.0/16)"]
            subgraph Public["Public Subnet"]
                NAT[NAT Gateway]
                Bastion["Bastion (Optional)"]
            end

            subgraph Private["Private Subnet"]
                EC2["Windows Server 2022 EC2<br/>(SSM管理・Session Manager)"]
                FSx["Amazon FSx for<br/>Windows File Server<br/>(Input/Output/Workspace/Temp/Logs)"]
            end

            VPCE["VPC Endpoints<br/>(SSM/S3/Logs/Secrets Manager)"]
        end

        IGW[Internet Gateway]
        S3["S3 Buckets<br/>(input/output/scripts/logs/artifacts)"]
        SecretsManager[Secrets Manager]
        KMS[KMS 共通CMK]
        CWLogs[CloudWatch Logs]
        CWAlarm[CloudWatch Alarms]
        SNS["SNS (Optional)"]
        IAM["IAM Role / Instance Profile"]
    end

    Admin -->|Session Manager| EC2
    Admin -.->|RDP 必要時のみ| Bastion
    Bastion -.->|RDP| EC2

    EC2 -->|SMB 445| FSx
    EC2 -->|IAM Role経由| S3
    EC2 -->|CloudWatch Agent| CWLogs
    EC2 -->|IAM Role経由| SecretsManager
    EC2 -.->|VPCエンドポイント経由| VPCE
    EC2 --> NAT
    NAT --> IGW

    CWLogs --> CWAlarm
    CWAlarm --> SNS

    KMS -.->|暗号化| S3
    KMS -.->|暗号化| FSx
    KMS -.->|暗号化| EC2
    KMS -.->|暗号化| SecretsManager
    KMS -.->|暗号化| CWLogs

    IAM -.->|AssumeRole| EC2
```

### 利用サービス

| サービス | 用途 |
|---|---|
| VPC / Subnet / IGW / NAT Gateway / Route Table | ネットワーク基盤 |
| VPC Endpoint (Interface/Gateway) | Private SubnetからNATを介さずSSM/S3等へ接続 |
| EC2 (Windows Server 2022) | デスクトップアプリケーション実行基盤 |
| Amazon FSx for Windows File Server | SMB共有ストレージ (Input/Output/Workspace/Temp/Logs) |
| Systems Manager (SSM) | Session Manager管理、Run Command/State Managerによるスクリプト実行 |
| CloudWatch Logs / Agent / Alarm | Windows Event Log・PowerShellログ等の収集、CPU/メモリ/ディスク/FSx監視 |
| Secrets Manager | アプリケーション認証情報の安全な管理 |
| KMS | EBS/S3/FSx/Secrets Manager/CloudWatch Logsの暗号化 |
| S3 | input/output/scripts/logs/artifacts用バケット |
| IAM Role / Instance Profile | EC2への最小権限付与 |
| SNS (オプション) | アラーム通知 |
| EventBridge | EC2停止検知・SSM Compliance異常検知 / **S3 ObjectCreatedイベントによるジョブ起動トリガー** |
| Lambda | **Job Dispatcher: S3イベント受信・ジョブID生成・SSM Run Command発行** |
| Step Functions (オプション) | **ジョブ状態(SSMコマンド完了)のポーリング管理・タイムアウト制御** |

### ディレクトリ構成

```
tf-win/
├── modules/
│   ├── network/        # VPC, Subnet, IGW, NAT, Route Table, VPC Endpoint
│   ├── ec2/             # Windows EC2, UserData
│   ├── fsx/             # FSx for Windows File Server
│   ├── s3/              # S3バケット群 (EventBridge通知設定含む)
│   ├── iam/             # IAM Role / Instance Profile / 最小権限ポリシー
│   ├── monitoring/      # CloudWatch Alarm(CPU/メモリ/ディスク/FSx/EC2), SNS, EventBridge
│   ├── security/        # KMS, Security Group, Secrets Manager
│   ├── logging/         # CloudWatch Logsロググループ
│   ├── ssm/             # SSMドキュメント(セットアップ/Launcher起動), State Manager Association
│   ├── lambda/          # Job Dispatcher Lambda (S3イベント→SSM Run Command)
│   ├── eventbridge/     # S3 ObjectCreatedイベントルール(Lambda/Step Functionsターゲット切替)
│   ├── stepfunctions/   # ジョブ状態ポーリング用ステートマシン(オプション)
│   └── cloudwatch/      # Lambda/SSM/ジョブ実行に関するCloudWatch Alarm
├── launcher/
│   ├── launcher.ps1     # 共通Launcher(入力取得→アプリ起動→出力アップロード)
│   └── config/          # アプリケーション設定(JSON)。差し替えのみで対象アプリを変更可能
├── apps/
│   └── sample-uppercase/ # 動作確認用サンプルアプリ(入力テキストを大文字変換)
├── environments/
│   ├── dev/             # dev環境 (backend, tfvars)
│   ├── stg/             # stg環境
│   └── prod/            # prod環境
├── scripts/             # 初期セットアップスクリプト配置場所(本Terraformの管理外)
├── main.tf              # ルートモジュール(各サブモジュールの結線)
├── variables.tf
├── outputs.tf
├── locals.tf
├── versions.tf
└── README.md
```

`environments/<env>` はルートモジュール(`main.tf`)を呼び出す薄いラッパーです。
環境固有の値(backend設定、tfvars)のみを持ち、リソース定義自体は `modules/` に
集約することで環境間の差分を最小化し、保守性を高めています。

### 設計方針

- **モジュール化の徹底**: 責務ごとにモジュールを分割し、再利用性・可読性を高める。
- **変数化・locals活用**: ハードコードを避け、タグは `locals.common_tags` で一元管理。
- **最小権限**: IAM Roleは必要なアクション・リソースのみを許可。
- **Session Manager優先**: RDPを常時開放せず、SSM Session Managerによる管理を基本とする。
- **暗号化の徹底**: EBS/S3/FSx/Secrets Manager/CloudWatch Logsを共通KMS CMKで暗号化。
- **アプリケーション非依存**: 特定アプリケーションに依存する実装・命名を避け、
  任意のWindows GUIアプリケーションに対応できる汎用基盤とする。
- **セットアップ処理の責務分離**: Terraformはスクリプトを実行可能な状態にするまでとし、
  スクリプトの中身(ランタイム導入等)は運用チームが管理する。

---

## イベント駆動ジョブ実行基盤

`enable_event_driven_job_execution = true` を設定することで、S3 Inputバケットへの
ファイルアップロードをトリガーに、Windowsアプリケーションの実行から結果取得までを
AWSサービスによって自動化するイベント駆動ジョブ実行基盤を追加構築できます。

Windows側にフォルダ監視サービス(FileSystemWatcher等)を常駐させる方式ではなく、
サーバーレスのAWSイベント駆動を採用することで、Windows EC2は「実際のアプリケーション実行」
のみを担当し、ジョブ投入・管理はAWSマネージドサービス側に寄せています
(AWS Well-Architected Frameworkの運用性・信頼性の柱に沿った設計判断です)。

### システム概要

- **疎結合設計**: Lambda(Job Dispatcher)はS3イベントの受信・ジョブID生成・
  SSM Run Commandの発行のみを担当し、Windowsアプリケーションの実行ファイル名や
  コマンドライン引数など「アプリケーションの詳細」を一切知りません。
- **Launcherによるインターフェース共通化**: Windows側にはLauncher(`launcher.ps1`)のみを
  配置し、入力取得・作業ディレクトリ作成・アプリ起動・終了コード取得・ログ出力・
  出力アップロード・終了通知の責務のみを持たせます。対象アプリケーションは
  `launcher/config/<AppConfigName>.json` の実行ファイルパス・引数定義を差し替えるだけで
  切り替え可能です(HFSS/CAD/CAE/独自EXEいずれも同一の仕組みで対応)。
- **FSxをジョブ作業領域として利用**: ジョブごとに `Workspace/{JobId}` ディレクトリを
  作成し、入力/出力/一時ファイルを分離します。
- **Step Functionsはオプション**: `use_step_functions = true` の場合、EventBridgeの後続を
  Step Functionsに切り替え、SSMコマンドの完了をポーリングしてジョブの成功/失敗/
  タイムアウトを判定できます(後述のトレードオフ参照)。

### AWSアーキテクチャ図

```mermaid
flowchart LR
    User[ユーザー] -->|ファイルアップロード| S3Input["S3 Input Bucket"]
    S3Input -->|ObjectCreated Event| EventBridge["Amazon EventBridge"]

    subgraph Dispatch["ジョブディスパッチ(サーバーレス)"]
        EventBridge -->|直接起動 or| Lambda["AWS Lambda<br/>Job Dispatcher"]
        EventBridge -.->|Step Functions利用時| SFN["AWS Step Functions<br/>(ジョブ状態ポーリング)"]
        SFN -.->|Invoke| Lambda
    end

    Lambda -->|ssm:SendCommand| SSM["Systems Manager<br/>Run Command"]
    SFN -.->|ssm:GetCommandInvocation| SSM

    SSM -->|Launcher起動| EC2["Windows EC2<br/>PowerShell Launcher"]
    EC2 -->|入力取得/出力書込| FSx["Amazon FSx<br/>Workspace/{JobId}"]
    EC2 -->|任意Windowsアプリ起動| App["対象Windowsアプリケーション<br/>(HFSS/CAD/CAE/独自EXE等)"]
    EC2 -->|出力アップロード| S3Output["S3 Output Bucket"]
    EC2 -->|ログ出力| CWLogs["CloudWatch Logs"]

    Lambda -->|ログ出力| CWLogs
    SSM -->|実行ログ| CWLogs
    CWLogs --> CWAlarm["CloudWatch Alarm<br/>(Lambda Error/Timeout,<br/>SSM失敗, EC2オフライン)"]
    CWAlarm -.->|オプション| SNS["SNS通知"]
```

### シーケンス図

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant S3In as S3 Input Bucket
    participant EB as EventBridge
    participant L as Lambda(Job Dispatcher)
    participant SFN as Step Functions(任意)
    participant SSM as Systems Manager
    participant EC2 as Windows EC2(Launcher)
    participant FSx as Amazon FSx
    participant S3Out as S3 Output Bucket

    User->>S3In: ファイルアップロード(sample.txt)
    S3In->>EB: ObjectCreated Event
    alt Step Functions利用時
        EB->>SFN: StartExecution
        SFN->>L: Invoke(Lambda呼び出し)
    else Lambda直接起動
        EB->>L: Invoke
    end
    L->>L: ジョブID生成
    L->>SSM: SendCommand(launcher.ps1起動)
    SSM-->>L: CommandId, InstanceId
    opt Step Functions利用時
        loop ポーリング(最大max_poll_attempts回)
            SFN->>SSM: GetCommandInvocation
            SSM-->>SFN: Status(Pending/InProgress/Success/Failed)
        end
    end
    SSM->>EC2: launcher.ps1実行
    EC2->>S3In: 入力ファイル取得(Read-S3Object)
    EC2->>FSx: Workspace/{JobId} 作成・入出力配置
    EC2->>EC2: 対象Windowsアプリケーション起動
    EC2->>EC2: 終了コード取得・ログ出力
    EC2->>S3Out: 出力ファイルアップロード(Write-S3Object)
    EC2-->>SSM: 終了コード返却
    EC2->>EC2: CloudWatch Logsへ完了ログ出力(job_completed)
```

### ジョブ実行フロー(概要)

```
入力ファイルアップロード (S3 Input)
        ↓
ObjectCreated Event (EventBridge)
        ↓
Job Dispatcher Lambda (ジョブID生成・SSM Run Command発行)
        ↓
Systems Manager Run Command
        ↓
Windows EC2: PowerShell Launcher実行
   ├─ 入力ファイル取得 (S3 → FSx Workspace/{JobId})
   ├─ 作業ディレクトリ作成
   ├─ 対象Windowsアプリケーション起動 (config駆動)
   ├─ 終了コード取得・ログ出力
   └─ 出力ファイル保存 (FSx → S3 Output)
        ↓
S3 Output Bucket (処理結果)
```

### Lambdaデプロイ方法

Lambdaのソースコードは [modules/lambda/src/index.py](./modules/lambda/src/index.py) にあり、
`terraform apply` 実行時に `archive_file` データソースが自動的にZIP化してデプロイします。
コード変更後は追加の手順なく `terraform plan` / `terraform apply` を実行するだけで
`source_code_hash` の差分により再デプロイされます。

```bash
# コード変更後、差分確認のうえ適用
cd environments/dev
terraform plan -target=module.lambda
terraform apply -target=module.lambda
```

手動でZIPの中身を確認したい場合は次のように実行できます。

```bash
cd modules/lambda
zip -r /tmp/job-dispatcher-check.zip src
unzip -l /tmp/job-dispatcher-check.zip
```

### Launcher差し替え方法

Launcher自体(`launcher/launcher.ps1`)はアプリケーションの詳細を持たない共通実装のため、
通常はアプリケーション設定(JSON)の追加・変更のみで対応できます。

1. `launcher/config/<新しい設定名>.json` を作成し、対象アプリケーションの
   実行ファイルパス・引数(`{input}` `{output}` `{workdir}` `{config}` プレースホルダ利用可)・
   出力ファイル名を定義する。
2. アプリケーション本体・依存ランタイムをWindows EC2側にインストールする
   (本Terraformの責務外。初期セットアップスクリプトまたは別途手順で対応)。
3. `terraform.tfvars` の `default_app_config_name` を新しい設定名に変更するか、
   ジョブごとに異なるアプリを使い分けたい場合はLambda呼び出し元(EventBridgeルールの
   キープレフィックス等)で `appConfigName` パラメータを出し分ける。
4. `scripts` バケットへ `launcher.ps1` および設定ファイルをアップロードする
   (SSMドキュメントが実行時にダウンロードして利用する)。

Launcher自体を改修する必要があるケース(例: 複数出力ファイル対応、進捗レポート追加等)は
[launcher/launcher.ps1](./launcher/launcher.ps1) を直接編集し、責務(入力取得・作業ディレクトリ
作成・起動・終了コード取得・ログ出力・出力保存・終了通知)を超えないよう留意してください。

### 新しいWindowsアプリケーション追加方法

1. アプリケーション本体をWindows EC2上へインストール(初期セットアップスクリプトまたは
   AMI/ゴールデンイメージへ組み込み)。
2. `launcher/config/<app-name>.json` を作成:
   ```json
   {
     "executable": "C:\\Apps\\MyApp\\App.exe",
     "arguments": ["--input", "{input}", "--output", "{output}", "--workdir", "{workdir}", "--config", "{config}"],
     "outputFileName": "result.dat"
   }
   ```
3. `scripts` バケットへ設定ファイルをアップロード。
4. `terraform.tfvars` の `default_app_config_name` を切り替えるか、SSM Run Command呼び出し時の
   `appConfigName` パラメータで指定。
5. Terraform/AWS側の変更は一切不要(Lambda/EventBridge/SSMドキュメントはアプリケーションに
   依存しない設計のため)。

### Step Functions採用のメリット・デメリット

| 観点 | Lambda直接起動 (`use_step_functions=false`) | Step Functions経由 (`use_step_functions=true`) |
|---|---|---|
| メリット | 構成がシンプル、レイテンシが最小、コストが低い | ジョブの状態遷移(実行中/成功/失敗/タイムアウト)を可視化・管理しやすい。ポーリング・リトライ・タイムアウト処理を宣言的に記述できる。実行履歴がStep Functionsコンソールで追跡可能 |
| デメリット | ジョブの完了検知・タイムアウト管理は別途実装が必要(CloudWatch Logsベースの監視に依存) | 構成要素が増え保守対象が増加。ポーリング方式のためSSMコマンド完了までLambda Invoke課金が発生し続ける(比較的軽微だが考慮要) |
| 推奨ケース | シンプルな用途、ジョブ完了通知が不要、コスト最小化を優先する場合 | ジョブの実行履歴管理・複雑なエラーハンドリング・将来的なワークフロー拡張(複数ステップの処理)を見込む場合 |

将来的にジョブ前後に複数ステップ(前処理→アプリ実行→後処理→通知等)を追加する場合は
Step Functionsへの移行が容易な設計としています。

### トラブルシューティング(イベント駆動ジョブ実行基盤)

| 症状 | 想定原因 | 対処 |
|---|---|---|
| ファイルをアップロードしてもジョブが起動しない | S3バケットのEventBridge通知が無効、またはEventBridgeルールのキープレフィックス不一致 | `enable_event_driven_job_execution=true` か確認。`job_input_key_prefix` とアップロードキーが一致するか確認 |
| Lambdaのログに `ssm_send_command_failed` が出力される | 対象EC2のSSM Agentがオフライン、またはIAM権限不足 | EC2のSSM接続状況を `aws ssm describe-instance-information` で確認。Lambda実行ロールのSSM権限を確認 |
| SSM実行は成功するが出力ファイルが生成されない | Launcher内でアプリケーションが異常終了、または `outputFileName` の設定ミス | CloudWatch Logs `job-execution-log` ロググループでLauncherの構造化ログ(`app_exited`, `output_file_missing`等)を確認 |
| Step Functionsの実行がタイムアウトする | `max_poll_attempts` × `poll_interval_seconds` がアプリケーションの想定実行時間より短い | 変数を調整するか、長時間ジョブの場合は非同期通知方式への変更を検討 |
| Lambdaがタイムアウトする | `lambda_timeout_seconds` が短すぎる、SSM API呼び出しの遅延 | Lambdaは本来SSM SendCommandの発行のみのため長時間化は稀。CloudWatch Logsでボトルネックを確認 |

---

## 前提ソフトウェア

| ソフトウェア | 用途 | 参考バージョン |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | IaC実行 | >= 1.9.0 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS認証・操作補助 | v2系 |
| [Git](https://git-scm.com/) | バージョン管理 | 最新 |
| PowerShell | セットアップスクリプト作成・Session Manager経由の操作 | 5.1以降 / PowerShell 7 |
| [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | `aws ssm start-session` のCLI利用 | 最新 |
| (推奨) [tflint](https://github.com/terraform-linters/tflint) | Terraform静的解析 | 最新 |
| (推奨) [tfsec](https://github.com/aquasecurity/tfsec) | Terraformセキュリティスキャン | 最新 |

---

## AWS認証情報の設定方法

### Windows

#### AWS CLIインストール

1. [AWS CLI公式インストーラ (MSI)](https://awscli.amazonaws.com/AWSCLIV2.msi) をダウンロードして実行する。
2. インストール後、コマンドプロンプトまたはPowerShellで確認する。

   ```powershell
   aws --version
   ```

#### `aws configure` の実行方法

```powershell
aws configure --profile myprofile-dev
```

対話式でAccess Key ID / Secret Access Key / Default region name / Default output format を入力する。

#### 認証情報の保存場所

- `C:\Users\<User>\.aws\credentials`
- `C:\Users\<User>\.aws\config`

`credentials` にはアクセスキー等の機微情報、`config` にはリージョンやプロファイル固有の設定
(SSO設定含む)が保存される。

#### 環境変数を利用する方法

PowerShellの例:

```powershell
$env:AWS_ACCESS_KEY_ID = "AKIA..."
$env:AWS_SECRET_ACCESS_KEY = "..."
$env:AWS_SESSION_TOKEN = "..."   # 一時認証情報利用時のみ
$env:AWS_DEFAULT_REGION = "ap-northeast-1"
```

#### IAM Identity Center (旧AWS SSO) を利用する方法

```powershell
aws configure sso
```

プロンプトに従いSSO開始URL・リージョン・ロールを選択する。`~/.aws/config`
(Windowsでは `C:\Users\<User>\.aws\config`) に `sso_session` を含むプロファイルが作成される。

```powershell
aws sso login --profile myprofile-sso
```

#### 複数Profileの利用方法

`~/.aws/credentials` や `~/.aws/config` に `[profile1]`, `[profile2]` のように
複数プロファイルを定義できる。

#### Terraform実行時に利用するProfileの指定方法

本プロジェクトでは `aws_profile` 変数でプロファイルを指定する(`environments/<env>/terraform.tfvars`)。

```hcl
aws_profile = "myprofile-dev"
```

または環境変数で上書きすることも可能:

```powershell
$env:AWS_PROFILE = "myprofile-dev"
terraform plan
```

---

### macOS

#### AWS CLIインストール

Homebrewでのインストール例:

```bash
brew install awscli
aws --version
```

または[公式pkgインストーラ](https://awscli.amazonaws.com/AWSCLIV2.pkg)を利用する。

#### `aws configure` の実行方法

```bash
aws configure --profile myprofile-dev
```

#### 認証情報の保存場所

- `~/.aws/credentials`
- `~/.aws/config`

#### 環境変数を利用する方法

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."   # 一時認証情報利用時のみ
export AWS_DEFAULT_REGION="ap-northeast-1"
```

#### IAM Identity Center (旧AWS SSO) を利用する方法

```bash
aws configure sso
aws sso login --profile myprofile-sso
```

#### 複数Profileの利用方法

`~/.aws/credentials`, `~/.aws/config` に複数の `[profile]` セクションを定義し、
`--profile` オプションやAWS_PROFILE環境変数で切り替える。

#### Terraform実行時のProfile指定方法

```bash
export AWS_PROFILE=myprofile-dev
terraform plan
```

または `terraform.tfvars` の `aws_profile` 変数で指定する。

---

### セキュリティ上の注意事項

- **credentialsファイルはGit管理しない。** `.gitignore` で `.aws/`, `credentials`, `config`
  を除外している(本リポジトリの [.gitignore](./.gitignore) 参照)。
- **Access KeyをTerraformコードへ直接記述しない。** `provider "aws"` ブロックに
  `access_key` / `secret_key` を書かず、必ずプロファイルや環境変数、IAMロール経由で認証する。
- **`.gitignore` 例** (抜粋、詳細は [.gitignore](./.gitignore) 参照):

  ```gitignore
  *.tfvars
  !*.tfvars.example
  *.tfstate
  *.tfstate.*
  .terraform/
  .aws/
  credentials
  config
  ```

- **IAMユーザーではなくIAM Identity Center利用を推奨する理由**: 長期の固定Access Keyを
  払い出す必要がなく、多要素認証・一時認証情報の自動失効・一元的なアクセス管理が可能なため、
  漏洩時のリスクと運用負荷を大幅に低減できる。
- **本番環境では長期Access Keyよりも一時認証情報を推奨する理由**: 一時認証情報
  (STSトークン、SSO、IAM Role AssumeRole等)は有効期限が短く、漏洩時の被害範囲が
  限定される。CI/CDではOIDC連携によるロールAssumeを推奨する。
- **Secrets ManagerとTerraformの役割分担**: Terraformはシークレットの「箱」
  (Secrets Managerリソースそのもの、KMS暗号化設定、IAMアクセス権限)を作成するに留め、
  実際の機密値(パスワード・APIキー等)はplaceholderとして作成し、
  `aws secretsmanager put-secret-value` 等で運用担当者が別途投入する設計とする。
  これによりtfstate・Gitリポジトリに機微情報が平文で残ることを防ぐ。

---

## Terraform実行方法

### 事前準備: リモートステート用S3バケット/DynamoDBテーブル

各 `environments/<env>/main.tf` の `backend "s3"` ブロックは、事前に用意した
S3バケットとDynamoDBテーブル(ステートロック用)を参照する設計です。
初回利用時は以下のようなリソースを別途(本プロジェクト外で)作成し、
`bucket` / `dynamodb_table` の値を書き換えてください。

```bash
aws s3api create-bucket --bucket your-tfstate-bucket --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
aws dynamodb create-table --table-name your-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### tfvarsファイルの準備

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# 環境に合わせて値を編集する
```

### 初回: `terraform init`

```bash
cd environments/dev
terraform init
```

### 確認: `terraform plan`

```bash
terraform plan -var-file=terraform.tfvars
```

### 構築: `terraform apply`

```bash
terraform apply -var-file=terraform.tfvars
```

### 削除: `terraform destroy`

```bash
terraform destroy -var-file=terraform.tfvars
```

> **注意**: `s3_force_destroy = true` でない限り、バケット内にオブジェクトが
> 残っているとdestroyは失敗します。本番運用ではバケットの誤削除防止のため
> 意図的に `false` としています。

### Workspace利用例

環境ごとに `environments/<env>` ディレクトリを分離しているため、
Terraform Workspace機能は必須ではありませんが、同一環境内でさらに
分離したい場合(例: 一時的な検証用スタック)は以下のように利用できます。

```bash
terraform workspace new feature-x
terraform workspace select feature-x
terraform plan -var-file=terraform.tfvars
```

### Profile指定例

```bash
# 環境変数での指定
export AWS_PROFILE=myprofile-dev
terraform plan

# tfvarsでの指定 (aws_profile変数)
terraform plan -var-file=terraform.tfvars
```

### variables指定例

```bash
terraform apply -var-file=terraform.tfvars \
  -var="ec2_instance_type=m5.2xlarge" \
  -var="enable_rdp_access=true" \
  -var='rdp_allowed_cidrs=["203.0.113.10/32"]'
```

### tfvars利用例

`environments/<env>/terraform.tfvars.example` を参照してください。
主要な変数の意味は [variables.tf](./variables.tf) のdescriptionを参照してください。

---

## トラブルシューティング

| エラー | 原因 / 対処 |
|---|---|
| `Error: Backend initialization required, please run "terraform init"` | backend設定変更後は `terraform init -reconfigure` を実行する。 |
| `Error: error configuring S3 Backend: ... NoCredentialProviders` | AWS認証情報が設定されていない。`aws configure` またはプロファイル/環境変数を確認する。 |
| `Error: creating FSx ... InvalidParameterCombination` | FSx for Windows File ServerはActiveDirectory参加が必須。`fsx_self_managed_active_directory` 変数を設定するか、AD未整備の場合は `enable_fsx = false` にする。 |
| EC2にSession Managerで接続できない | ①IAM RoleにAmazonSSMManagedInstanceCoreがアタッチされているか、②Private SubnetからSSMエンドポイント(VPCエンドポイントまたはNAT経由)に到達できるか、③SSM Agentが起動しているか(数分待ってから再試行)を確認する。 |
| UserDataでのセットアップスクリプトが実行されない | `setup_script_execution_mode = "userdata"` になっているか、`scripts` バケットに指定した `setup_script_s3_key` が実在するか確認する。EC2の `C:\ProgramData\Amazon\setup-userdata.log` を確認する。 |
| `terraform plan` で毎回EC2が再作成される | AMI更新等が原因の場合は `modules/ec2` の `lifecycle.ignore_changes` でAMI変更を無視する設定を入れている。他の属性(サブネット等)の差分がないか確認する。 |
| `Error: "egress.0.description" doesn't comply with restrictions` | AWSのSecurity Group ルールの説明文は英数字と一部記号のみ許可される。日本語を含めないこと(本プロジェクトでは既に英語化済み)。 |
| S3バケット名が重複してcreateに失敗する | バケット名はグローバルに一意である必要がある。本プロジェクトはアカウントIDをバケット名に付与しているが、それでも衝突する場合は `s3_bucket_names` のサフィックスを変更する。 |
| ローカル環境に `pwsh`(PowerShell)や `tflint`/`tfsec` が無く静的解析が実行できない | サンドボックス/CI環境によっては未インストールの場合がある。Lambdaは `python3 -m py_compile` / `pyflakes` で代替可能。PowerShellはGitHub Actions等のWindows/Ubuntuランナー上で `Invoke-ScriptAnalyzer`(PSScriptAnalyzer)を利用したCIパイプラインの追加を推奨する(将来拡張のCI/CD項目を参照)。 |

---

## 設計判断理由 / 採用しなかった構成案

### FSx for Windows File Server を採用した理由

Windowsアプリケーションからは通常のSMB共有として認識でき、既存のWindows運用ノウハウを
そのまま活用できるため採用した。代替として **Amazon EFS** も検討したが、EFSはNFS
ベースでありWindowsからのネイティブSMBアクセスに標準対応しないため見送った。
ただし、FSx for Windows File ServerはActiveDirectory参加が必須という制約があるため、
AD未整備環境向けに `enable_fsx = false` でスキップ可能な設計とした。

### Session Manager優先、RDP常時開放を避けた理由

RDP(3389)の常時開放はインターネットからのブルートフォース攻撃・脆弱性悪用のリスクが
高い。Session Managerであれば、IAMベースの認可・CloudTrailによる操作証跡・
インバウンドポート開放不要という利点があるため、既定の管理手段とした。
RDPは運用上どうしても必要な場合のみ `enable_rdp_access` で限定的に有効化できる設計とし、
踏み台構成(`enable_bastion`)にも対応した。

### VPC Endpoint を導入した理由

Private SubnetからSSM/S3/CloudWatch Logs/Secrets Managerへの通信を、
NAT Gateway経由(インターネット向け経路)ではなくVPC内で完結させることで、
セキュリティ(不要なインターネット露出の回避)とコスト(NAT Gatewayのデータ転送料削減)
の両方を改善できるため採用した。小規模検証環境ではコスト増となるため
`enable_vpc_endpoints` でオプション化した。

### セットアップスクリプトの実行方式を3種類サポートした理由

- `userdata`: シンプルで初回起動時の自動化に適するが、後から再実行するには
  インスタンス再作成が必要になりがちで柔軟性に欠ける。
- `ssm_run_command`: 任意タイミングで手動/CI経由で実行でき、運用中の再セットアップや
  修正パッチ適用に向く。
- `state_manager`: 継続的なコンプライアンス維持(ドリフト自動是正)に向くが、
  意図せず再実行されるリスクもある。

用途に応じて切り替えられるよう変数化し、特定の一方式に固定しない設計とした。

### 採用しなかった構成案

- **AWS Managed Microsoft ADの自動構築**: FSxのAD参加要件を満たすために本来は
  Managed Microsoft ADも本プロジェクトに含めることが望ましいが、AD構成は
  既存のオンプレミスAD/他プロジェクトで管理されているケースが多く、
  汎用基盤としては「外部から接続情報を受け取る」設計の方が柔軟性が高いと判断し、
  `fsx_self_managed_active_directory` 変数経由で外部提供する設計とした
  (将来的にモジュールとして追加可能)。
- **Auto Scaling Group によるEC2管理**: デスクトップアプリケーションは
  ステートフルな作業環境(ユーザーセッション・ローカルデータ)であることが多く、
  スケールアウト/インによるインスタンス入れ替えとは相性が悪いため、
  現時点では固定台数のEC2(`ec2_instance_count`)とした。
  マルチユーザー化などの要件があれば将来拡張でASGを追加できる。
- **CloudFrontやALBの導入**: 対象がデスクトップGUIアプリケーション(RDP/SSMで
  直接操作)であり、HTTPロードバランシングの必要性がないため見送った。
  将来、Webベースの管理画面等を追加する場合はALBを追加できる設計としている。
- **Terraformによるスクリプト内容の直接記述**: bootstrap.ps1等の中身を
  Terraformのheredocやtemplatefileで管理する案もあったが、アプリケーション
  ごとに大きく異なる内容をTerraformのライフサイクルに巻き込むと、
  些細なスクリプト変更のたびにTerraformの差分・レビューが必要になり保守性が
  低下するため、スクリプト自体は別リポジトリ/別ファイルとして管理し、
  Terraformは「配置・実行できる状態にする」ことに専念する設計とした。
- **Windows側でのフォルダ監視常駐サービス方式**: FileSystemWatcher等をWindows側で
  常駐させ、S3同期エージェント経由でポーリングする方式も検討したが、
  (1)Windows側に監視プロセスの維持・障害対応という運用負荷が発生する、
  (2)スケールアウト時に複数インスタンスでの重複実行制御が複雑になる、
  という理由から、AWS側のイベント駆動(EventBridge)を採用し、Windows側は
  「呼び出されたら実行するだけ」のステートレスな構成とした。
- **Lambdaによるアプリケーション実行そのものの代替(コンテナ化)**: Windows GUI/
  デスクトップアプリケーション(HFSS/CAD等)の多くはLambda上のコンテナや
  Fargateでは動作しない(GUI依存・ライセンスドングル・Windows専用ドライバ等)ため、
  実行部分はWindows EC2に残し、Lambdaは「呼び出すだけ」の薄い層とした。
- **SSM GetCommandInvocationのコールバック統合**: Step Functionsのタスクトークン
  (`waitForTaskToken`)によるコールバック待受を検討したが、SSM Run Command自体が
  Step Functionsへの完了通知(コールバック)を標準でサポートしていないため、
  ポーリング方式(Wait→GetCommandInvocation→Choice)を採用した。将来SSMが
  EventBridge経由の完了通知に対応した場合は、コールバック方式への移行を検討する。

---

## 将来拡張

以下の要件は本プロジェクトの構成(モジュール分割・変数化)を維持したまま、
モジュール追加や変数拡張で対応できます。

- **GPUインスタンス**: `ec2_instance_type` をGPUインスタンスタイプ(g4dn等)に
  変更するだけで対応可能(ドライバ導入はセットアップスクリプト側)。
- **Auto Scaling / 複数Windowsサーバー**: `ec2_instance_count` は既に複数台数対応済み。
  ASG化する場合は `modules/ec2` を Launch Template + ASG構成に拡張する。
- **Step Functions / EventBridge / Lambda**: 本改修で実装済み(`modules/eventbridge`,
  `modules/lambda`, `modules/stepfunctions`)。`enable_event_driven_job_execution` /
  `use_step_functions` 変数で有効化・切替が可能。
- **AWS Batch**: SSM Run Command方式の代わりにAWS Batch(Windows対応コンテナ/EC2)へ
  ジョブを投入する構成へ拡張する場合は、Lambda内の `_send_command` をBatch SubmitJobへ
  差し替えることで対応可能(Launcherインターフェースはそのまま流用できる)。
- **S3イベント**: 本改修で実装済み(`aws_s3_bucket_notification` の `eventbridge = true` 設定)。
- **AWS Managed Microsoft AD / ドメイン参加**: `modules/fsx` は既に
  `self_managed_active_directory` ブロックで外部AD接続に対応済みのため、
  Managed AD構築モジュールを追加し出力値を渡すだけで統合できる。
- **GitHub Actions / CodePipeline / CodeBuild**: 本プロジェクトはtfvarsとbackendを
  環境ごとに分離済みのため、CI/CDパイプラインからは
  `terraform plan/apply -var-file=environments/<env>/terraform.tfvars` を
  実行するだけで組み込み可能。
- **Application Load Balancer**: `modules/network` のPublic Subnetを活用し、
  新規モジュールとして追加可能。
- **ライセンスサーバー追加/複数アプリケーションの同居**: 本基盤はアプリケーション
  非依存設計のため、追加のEC2インスタンス(`ec2_instance_count`増加)や
  S3/FSxの追加フォルダ(`fsx_shared_folders`)で対応可能。
- **SQSによるジョブキュー**: EventBridgeとLambdaの間にSQSを挟み、Lambdaの同時実行数
  (`lambda_reserved_concurrency`)を超えるバーストに対してバッファリングする構成へ
  容易に拡張可能(EventBridgeターゲットをSQSに変更し、Lambdaをイベントソースマッピングで駆動)。
- **複数Windows Worker / ジョブ優先度制御**: `target_tag_key`/`target_tag_value` による
  タグベースターゲティングを利用し、複数EC2へジョブを分散する構成に拡張できる。
  優先度制御が必要な場合はSQSの複数キュー(優先度別)+EventBridge Pipesの組み合わせを推奨。
- **ジョブキャンセル**: Step Functions利用時は `StopExecution` API、SSM側は
  `ssm:CancelCommand` を呼び出すキャンセル用Lambda/APIを追加することで対応可能。
- **実行履歴管理**: Step Functensの実行履歴に加え、DynamoDBにジョブメタデータ
  (JobId/Status/開始終了時刻/入出力パス)を記録するテーブルを追加し、
  LambdaまたはLauncherから書き込む構成へ拡張できる。
- **Web UI / API Gateway / 認証機能**: API Gateway + Lambda + Cognitoにより、
  ユーザーがブラウザからジョブ投入・進捗確認・結果ダウンロードを行えるUIを追加可能。
  現状のS3直接アップロード方式はAPI Gatewayの署名付きURL発行Lambdaに置き換えられる。
- **CI/CD (GitHub Actions)**: `terraform fmt/validate/plan` に加え、Lambda静的解析
  (`pyflakes`/`bandit`)、PowerShell構文チェック(`PSScriptAnalyzer`)を
  GitHub Actionsワークフローに組み込むことで、PR時の自動品質チェックが可能。
