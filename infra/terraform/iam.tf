# ─────────────────────────────────────────
# bq-subscriber: Pub/Sub SA のみ呼び出し可
# ─────────────────────────────────────────

resource "google_cloud_run_v2_service_iam_member" "bq_subscriber_pubsub_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.bq_subscriber.location
  name     = google_cloud_run_v2_service.bq_subscriber.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}

# ─────────────────────────────────────────
# サービスアカウント権限
# ─────────────────────────────────────────

# GCS 読み書き
resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${var.service_account_email}"
}

# BigQuery 書き込み
resource "google_project_iam_member" "sa_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${var.service_account_email}"
}

# BigQuery ジョブ実行
resource "google_project_iam_member" "sa_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.service_account_email}"
}

# Pub/Sub publish
resource "google_project_iam_member" "sa_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.service_account_email}"
}

# Vision API は API 有効化 + 認証済み SA で利用可能（追加 IAM 不要）

# ─────────────────────────────────────────
# Pub/Sub SA: OIDC トークン生成権限
# （Pub/Sub Push が Cloud Run に認証リクエストを送るために必要）
# ─────────────────────────────────────────

resource "google_project_iam_member" "pubsub_sa_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
