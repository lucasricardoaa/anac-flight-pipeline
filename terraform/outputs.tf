output "airflow_vm_ip" {
  description = "IP externo estático da VM do Airflow"
  value       = google_compute_address.airflow.address
}

output "airflow_webserver_url" {
  description = "URL do Airflow webserver"
  value       = "http://${google_compute_address.airflow.address}:8080"
}

output "bucket_bronze" {
  description = "Nome do bucket GCS da camada Bronze"
  value       = google_storage_bucket.bronze.name
}

output "bucket_silver" {
  description = "Nome do bucket GCS da camada Silver"
  value       = google_storage_bucket.silver.name
}

output "bucket_gold" {
  description = "Nome do bucket GCS da camada Gold"
  value       = google_storage_bucket.gold.name
}

output "sa_airflow_email" {
  description = "Email da service account do Airflow"
  value       = google_service_account.airflow.email
}

output "sa_dataproc_email" {
  description = "Email da service account do Dataproc"
  value       = google_service_account.dataproc.email
}
