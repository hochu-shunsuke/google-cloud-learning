variable "project_id" {
  description = "GCP プロジェクトID"
  type        = string
}

variable "region" {
  description = "GCP リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "service_account_email" {
  description = <<-EOT
    Cloud Run / Cloud Functions 実行サービスアカウント
    デフォルト Compute SA: PROJECT_NUMBER-compute@developer.gserviceaccount.com
  EOT
  type        = string
}

variable "upload_api_image" {
  description = <<-EOT
    image-upload-api の Docker イメージ URL
    gcloud run deploy --source . で自動生成されるイメージを指定
    例: asia-northeast1-docker.pkg.dev/PROJECT_ID/cloud-run-source-deploy/image-upload-api
  EOT
  type        = string
}

variable "bq_subscriber_image" {
  description = <<-EOT
    bq-subscriber の Docker イメージ URL
    例: asia-northeast1-docker.pkg.dev/PROJECT_ID/cloud-run-source-deploy/bq-subscriber
  EOT
  type        = string
}
