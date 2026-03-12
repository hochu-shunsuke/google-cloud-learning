# Phase 2: Terraform による Infrastructure as Code

Phase1〜4で手動作成した GCP リソースを Terraform でコード化します。  
インフラの状態をコードで管理することで、**再現性・変更履歴・チームでの共有**が可能になります。

## ディレクトリ構成

```
phase2-terraform/
├── main.tf                    # メインリソース定義（GCS / Pub/Sub / BigQuery / Cloud Run / Cloud Functions）
├── iam.tf                     # IAM 権限設定
├── variables.tf               # 変数定義
├── outputs.tf                 # 出力値（URL など）
├── terraform.tfvars.example   # 変数値のサンプル
└── .gitignore                 # tfstate・秘密情報を除外
```

## 管理するリソース

| リソース | 種類 | 説明 |
|---------|------|------|
| `gen-lang-client-0213648671-images` | Cloud Storage | 画像保存バケット |
| `image-analysis-results` | Pub/Sub Topic | 解析結果配信 |
| `image-analysis-sub` | Pub/Sub Subscription (Pull) | デバッグ用 |
| `image-analysis-push-sub` | Pub/Sub Subscription (Push) | BQ サブスクライバー呼び出し |
| `image_analysis.results` | BigQuery Table | 解析結果テーブル |
| `image-upload-api` | Cloud Run | 画像アップロードAPI |
| `bq-subscriber` | Cloud Run | BigQuery 書き込みサービス |
| `analyze-image` | Cloud Functions v2 | Vision AI 解析 |
| `cloud-run-repo` | Artifact Registry | Docker イメージ保管 |

## セットアップ手順

### 1. 前提条件

```bash
# Terraform インストール（未インストールの場合）
brew install terraform

# バージョン確認
terraform version  # >= 1.5 が必要
```

### 2. 変数ファイルを作成

```bash
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集して実際の値を入力:

```hcl
project_id            = "gen-lang-client-0213648671"
region                = "asia-northeast1"

# プロジェクト番号の確認: gcloud projects describe gen-lang-client-0213648671 --format="value(projectNumber)"
service_account_email = "YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com"

# イメージ URL の確認: gcloud run services describe image-upload-api --region=asia-northeast1 --format="value(spec.template.spec.containers[0].image)"
upload_api_image      = "asia-northeast1-docker.pkg.dev/gen-lang-client-0213648671/cloud-run-source-deploy/image-upload-api"
bq_subscriber_image   = "asia-northeast1-docker.pkg.dev/gen-lang-client-0213648671/cloud-run-source-deploy/bq-subscriber"
```

### 3. 初期化

```bash
cd phase2-terraform
terraform init
```

### 4. 既存リソースの Import（重要）

Phase1〜4 で作成済みのリソースを Terraform 管理下に移行します。  
`terraform apply` をそのまま実行すると**既存リソースと競合**するため、必ず import を先に行ってください。

```bash
PROJECT=gen-lang-client-0213648671
REGION=asia-northeast1

# GCS バケット
terraform import google_storage_bucket.images ${PROJECT}-images

# Pub/Sub
terraform import google_pubsub_topic.image_analysis_results projects/${PROJECT}/topics/image-analysis-results
terraform import google_pubsub_subscription.image_analysis_sub projects/${PROJECT}/subscriptions/image-analysis-sub

# BigQuery
terraform import google_bigquery_dataset.image_analysis ${PROJECT}:image_analysis
terraform import google_bigquery_table.results ${PROJECT}:image_analysis.results

# Cloud Run
terraform import google_cloud_run_v2_service.image_upload_api projects/${PROJECT}/locations/${REGION}/services/image-upload-api
terraform import google_cloud_run_v2_service.bq_subscriber projects/${PROJECT}/locations/${REGION}/services/bq-subscriber

# Cloud Functions
terraform import google_cloudfunctions2_function.analyze_image projects/${PROJECT}/locations/${REGION}/functions/analyze-image
```

### 5. 差分確認

```bash
terraform plan
```

### 6. 適用

```bash
terraform apply
```

## 新規環境への展開（ゼロから作る場合）

Import 不要で `terraform apply` のみで全リソースを作成できます。  
ただし Cloud Run のイメージは事前にビルドが必要です:

```bash
# 各フェーズでイメージをビルド（Cloud Run がイメージを参照するため）
gcloud run deploy image-upload-api --source ../phase1-cloud-run --region asia-northeast1 --no-traffic
gcloud run deploy bq-subscriber --source ../phase4-bigquery --region asia-northeast1 --no-traffic

# その後 Terraform で設定を統一管理
terraform apply
```

## Terraform の基本コマンド

```bash
terraform init      # プロバイダーダウンロード
terraform plan      # 変更差分の確認（適用はしない）
terraform apply     # 適用
terraform destroy   # 全リソース削除（注意）
terraform output    # 出力値の確認
terraform state list  # 管理中リソース一覧
```
