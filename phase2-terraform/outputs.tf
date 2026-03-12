output "image_upload_api_url" {
  description = "画像アップロードAPI エンドポイント"
  value       = google_cloud_run_v2_service.image_upload_api.uri
}

output "bq_subscriber_url" {
  description = "BigQuery サブスクライバー エンドポイント"
  value       = google_cloud_run_v2_service.bq_subscriber.uri
}

output "analyze_image_url" {
  description = "Vision AI 解析 Cloud Function エンドポイント"
  value       = google_cloudfunctions2_function.analyze_image.service_config[0].uri
}

output "gcs_bucket_name" {
  description = "画像保存 GCS バケット名"
  value       = google_storage_bucket.images.name
}

output "pubsub_topic_name" {
  description = "Pub/Sub トピック名"
  value       = google_pubsub_topic.image_analysis_results.name
}

output "bq_table_fqn" {
  description = "BigQuery テーブル フルパス"
  value       = "${var.project_id}.${google_bigquery_dataset.image_analysis.dataset_id}.${google_bigquery_table.results.table_id}"
}

output "pubsub_invoker_sa_email" {
  description = "Pub/Sub Push 用サービスアカウント"
  value       = google_service_account.pubsub_invoker.email
}
