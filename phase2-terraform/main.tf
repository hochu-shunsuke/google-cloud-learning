terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # ローカル tfstate（学習用）
  # 本番では GCS backend を推奨:
  # backend "gcs" {
  #   bucket = "gen-lang-client-0213648671-tfstate"
  #   prefix = "google-cloud-learning"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# プロジェクト情報（project_number 取得用）
data "google_project" "current" {}

# ─────────────────────────────────────────
# Cloud Storage
# ─────────────────────────────────────────

# 画像保存バケット
resource "google_storage_bucket" "images" {
  name                        = "${var.project_id}-images"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  lifecycle_rule {
    action { type = "Delete" }
    condition { age = 365 } # 1年後に自動削除（コスト管理）
  }
}

# Cloud Functions ソースコード保存バケット
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-function-source"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

# ─────────────────────────────────────────
# Artifact Registry
# ─────────────────────────────────────────

resource "google_artifact_registry_repository" "cloud_run" {
  location      = var.region
  repository_id = "cloud-run-repo"
  format        = "DOCKER"
  description   = "Cloud Run コンテナイメージ"
}

# ─────────────────────────────────────────
# Pub/Sub
# ─────────────────────────────────────────

resource "google_pubsub_topic" "image_analysis_results" {
  name = "image-analysis-results"

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

# Pull サブスクリプション（ローカルデバッグ・確認用）
resource "google_pubsub_subscription" "image_analysis_sub" {
  name  = "image-analysis-sub"
  topic = google_pubsub_topic.image_analysis_results.name

  ack_deadline_seconds       = 20
  retain_acked_messages      = false
  message_retention_duration = "86400s" # 1日
}

# ─────────────────────────────────────────
# BigQuery
# ─────────────────────────────────────────

resource "google_bigquery_dataset" "image_analysis" {
  dataset_id  = "image_analysis"
  location    = "US"
  description = "AI画像解析結果データセット"
}

resource "google_bigquery_table" "results" {
  dataset_id          = google_bigquery_dataset.image_analysis.dataset_id
  table_id            = "results"
  deletion_protection = false
  description         = "Vision API ラベル検出結果"

  schema = jsonencode([
    { name = "bucket_name", type = "STRING",    mode = "NULLABLE", description = "GCS バケット名" },
    { name = "object_name", type = "STRING",    mode = "NULLABLE", description = "オブジェクト名（ファイルパス）" },
    { name = "labels",      type = "STRING",    mode = "NULLABLE", description = "検出ラベル（カンマ区切り）" },
    { name = "description", type = "STRING",    mode = "NULLABLE", description = "代表ラベル名" },
    { name = "analyzed_at", type = "TIMESTAMP", mode = "NULLABLE", description = "解析日時（UTC）" },
  ])
}

# ─────────────────────────────────────────
# Cloud Functions v2: analyze-image
# ─────────────────────────────────────────

# phase3-ai-pipeline をzip圧縮してGCSにアップロード
data "archive_file" "analyze_image_source" {
  type        = "zip"
  source_dir  = "../phase3-ai-pipeline"
  output_path = "${path.module}/.tmp/analyze-image-source.zip"
  excludes    = [".git"]
}

resource "google_storage_bucket_object" "analyze_image_source" {
  name   = "function-source/analyze-image-${data.archive_file.analyze_image_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.analyze_image_source.output_path
}

resource "google_cloudfunctions2_function" "analyze_image" {
  name     = "analyze-image"
  location = var.region

  build_config {
    runtime     = "go125"
    entry_point = "AnalyzeImage"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.analyze_image_source.name
      }
    }
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = var.service_account_email
    environment_variables = {
      PROJECT_ID   = var.project_id
      PUBSUB_TOPIC = google_pubsub_topic.image_analysis_results.name
    }
  }
}

# ─────────────────────────────────────────
# Cloud Run: image-upload-api
# ─────────────────────────────────────────

resource "google_cloud_run_v2_service" "image_upload_api" {
  name     = "image-upload-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account_email
    containers {
      # イメージは `gcloud run deploy --source .` でビルド済みのものを参照
      # 例: asia-northeast1-docker.pkg.dev/PROJECT_ID/cloud-run-source-deploy/image-upload-api
      image = var.upload_api_image

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.images.name
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

# ─────────────────────────────────────────
# Cloud Run: bq-subscriber
# ─────────────────────────────────────────

# Pub/Sub が Cloud Run を呼び出すための専用 SA
resource "google_service_account" "pubsub_invoker" {
  account_id   = "cloud-run-pubsub-invoker"
  display_name = "Pub/Sub → Cloud Run Invoker"
}

resource "google_cloud_run_v2_service" "bq_subscriber" {
  name     = "bq-subscriber"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account_email
    containers {
      image = var.bq_subscriber_image

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BQ_DATASET"
        value = google_bigquery_dataset.image_analysis.dataset_id
      }
      env {
        name  = "BQ_TABLE"
        value = google_bigquery_table.results.table_id
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

# Pub/Sub → bq-subscriber への Push サブスクリプション
resource "google_pubsub_subscription" "image_analysis_push_sub" {
  name  = "image-analysis-push-sub"
  topic = google_pubsub_topic.image_analysis_results.name

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.bq_subscriber.uri}/pubsub"
    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
    }
  }

  ack_deadline_seconds = 60
}
