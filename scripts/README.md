# scripts/README

このディレクトリには、初期セットアップスクリプト(PowerShell)を配置します。

Terraformの責務は「スクリプトをEC2起動後に実行できる状態まで用意すること」までであり、
スクリプトの中身(アプリケーションインストール、Python/PowerShell/.NET/Visual C++
Runtime/Anacondaなどのランタイムセットアップ)は本Terraformの管理対象外です。
運用チームが実際の要件に応じて `bootstrap.ps1` 等を実装してください。

## 配置・反映手順

1. このディレクトリ配下にスクリプトを作成・編集する(例: `bootstrap.ps1`, `setup.ps1`, `install.ps1`)。
2. `terraform apply` 実行時、`aws s3 sync` 等でS3の `scripts` バケットへアップロードする
   (本リポジトリでは `terraform_data`/`null_resource` 等での自動アップロードはせず、
   CI/CDパイプラインまたは手動アップロードを推奨する。理由は README.md の
   「設計判断理由」を参照)。
3. `setup_script_execution_mode` 変数で実行方式を選択する。
   - `userdata`: EC2起動時にUserDataから自動的にS3から取得・実行される
   - `ssm_run_command`: 任意タイミングで `aws ssm send-command` を使い手動実行する
   - `state_manager`: SSM Associationにより自動適用される

## サンプルファイル

- `bootstrap.ps1`: プレースホルダーのサンプル。実際の処理は未実装。
