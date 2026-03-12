# Google Cloud Learning

Go言語を使って GCP 主要サービスを段階的に実装する学習プロジェクト。  
「画像アップロード → AI解析 → データ蓄積 → 可視化」という実践的なパイプラインを構築します。

## アーキテクチャ全体図

```
[クライアント]
    │
    │ POST /upload（画像）
    ▼
[Cloud Run: image-upload-api]  ─── 画像保存 ──▶ [Cloud Storage]
    │
    │ POST /analyze（bucket/object）
    ▼
[Cloud Functions: analyze-image]
    │  Vision API で画像解析
    │  （ラベル検出・確信度 70% 以上）
    │
    │ Pub/Sub publish
    ▼
[Pub/Sub: image-analysis-results]
    │
    │ Push サブスクリプション
    ▼
[Cloud Run: bq-subscriber]
    │
    │ BigQuery streaming insert
    ▼
[BigQuery: image_analysis.results]
    │
    │ SQL ビュー
    ▼
[Looker Studio ダッシュボード]
```

## フェーズ構成

| フェーズ | ディレクトリ | サービス | 内容 |
|---------|------------|---------|------|
| Phase1 | [phase1-cloud-run/](./phase1-cloud-run/) | Cloud Run + Cloud Storage | 画像アップロードAPI |
| Phase2 | [phase2-terraform/](./phase2-terraform/) | Terraform | 全リソースの Infrastructure as Code 化 |
| Phase3 | [phase3-ai-pipeline/](./phase3-ai-pipeline/) | Cloud Functions + Vision API + Pub/Sub | AI画像解析パイプライン |
| Phase4 | [phase4-bigquery/](./phase4-bigquery/) | Cloud Run + BigQuery | 解析結果のデータウェアハウス蓄積 |
| Phase5 | [phase5-looker-studio/](./phase5-looker-studio/) | Looker Studio | BIダッシュボード可視化 |

## 技術スタック

- **言語**: Go 1.25
- **インフラ管理**: Terraform
- **コンテナ**: Docker（マルチステージビルド）
- **リージョン**: `asia-northeast1`（東京）

## GCP サービス一覧

| サービス | 用途 |
|---------|------|
| Cloud Run | コンテナ実行（ゼロスケール） |
| Cloud Storage | 画像ファイル保存 |
| Cloud Functions (Gen2) | サーバーレスイベント処理 |
| Vision API | AI画像ラベル検出 |
| Pub/Sub | 非同期メッセージキュー |
| BigQuery | データウェアハウス |
| Looker Studio | BIダッシュボード |
| Artifact Registry | Docker イメージ管理 |

## セットアップ

### 前提条件

```bash
# 必要なツール
gcloud  # Google Cloud CLI
go      # Go 1.21+
terraform # Terraform 1.5+（Phase2のみ）
```

### Phase1: 画像アップロードAPI を動かす

```bash
cd phase1-cloud-run

gcloud run deploy image-upload-api \
  --source . \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --set-env-vars GCS_BUCKET=YOUR_BUCKET,GCP_PROJECT=YOUR_PROJECT
```

### Phase3: AI解析パイプラインを動かす

```bash
cd phase3-ai-pipeline

gcloud functions deploy analyze-image \
  --gen2 \
  --runtime go125 \
  --region asia-northeast1 \
  --entry-point AnalyzeImage \
  --trigger-http \
  --allow-unauthenticated \
  --set-env-vars PROJECT_ID=YOUR_PROJECT,PUBSUB_TOPIC=image-analysis-results
```

### Phase4: BigQuery サブスクライバーを動かす

```bash
cd phase4-bigquery

gcloud run deploy bq-subscriber \
  --source . \
  --region asia-northeast1 \
  --no-allow-unauthenticated \
  --set-env-vars PROJECT_ID=YOUR_PROJECT,BQ_DATASET=image_analysis,BQ_TABLE=results
```

### Phase2: Terraform で既存リソースを管理する

```bash
cd phase2-terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して値を入力

terraform init
terraform plan   # 変更差分を確認
terraform apply  # 適用
```

### Phase5: Looker Studio ダッシュボードを作成する

```bash
cd phase5-looker-studio

# BigQuery ビューを作成
bq query --use_legacy_sql=false --project_id=YOUR_PROJECT "$(cat views.sql)"

# その後 https://lookerstudio.google.com/ で可視化
```

## エンドツーエンドの動作確認

```bash
PROJECT=gen-lang-client-0213648671
UPLOAD_API=https://image-upload-api-rpycdgcciq-an.a.run.app
FUNCTION_URL=https://asia-northeast1-${PROJECT}.cloudfunctions.net/analyze-image

# 1. 画像をアップロード
curl -X POST ${UPLOAD_API}/upload \
  -F "image=@test.png"

# 2. AI解析を実行（bucket と object を指定）
curl -X POST ${FUNCTION_URL} \
  -H "Content-Type: application/json" \
  -d '{"bucket":"${PROJECT}-images","object":"uploads/xxx.png"}'

# 3. BigQuery で結果を確認
bq query --use_legacy_sql=false \
  'SELECT description, labels, analyzed_at FROM `'${PROJECT}'.image_analysis.results` ORDER BY analyzed_at DESC LIMIT 5'
```
