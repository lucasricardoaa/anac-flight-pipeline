# =============================================================================
# Service Accounts — ADR-08, [VERIFICAR #12]
# Roles mínimas por princípio de menor privilégio.
# =============================================================================

# Service account para a VM do Airflow
resource "google_service_account" "airflow" {
  account_id   = "sa-airflow"
  display_name = "ANAC Pipeline — Airflow"
  description  = "Usada pela VM e2-medium que executa o Airflow. Permissões para gerenciar cluster Dataproc, acessar buckets GCS e ler secrets."
}

# Service account para os workers do Dataproc
resource "google_service_account" "dataproc" {
  account_id   = "sa-dataproc"
  display_name = "ANAC Pipeline — Dataproc"
  description  = "Usada pelos workers do cluster Dataproc efêmero. Permissões para ler/escrever nos buckets GCS e atuar como worker Dataproc."
}

# --- Roles para sa-airflow ---

resource "google_project_iam_member" "airflow_dataproc_editor" {
  project = var.project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.airflow.email}"
}

resource "google_project_iam_member" "airflow_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.airflow.email}"
}

resource "google_storage_bucket_iam_member" "airflow_bronze" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.airflow.email}"
}

resource "google_storage_bucket_iam_member" "airflow_silver" {
  bucket = google_storage_bucket.silver.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.airflow.email}"
}

resource "google_storage_bucket_iam_member" "airflow_gold" {
  bucket = google_storage_bucket.gold.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.airflow.email}"
}

# --- Roles para sa-dataproc ---

resource "google_project_iam_member" "dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc.email}"
}

resource "google_storage_bucket_iam_member" "dataproc_bronze" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc.email}"
}

resource "google_storage_bucket_iam_member" "dataproc_silver" {
  bucket = google_storage_bucket.silver.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc.email}"
}

resource "google_storage_bucket_iam_member" "dataproc_gold" {
  bucket = google_storage_bucket.gold.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc.email}"
}

# Permissão para a VM assumir a service account do Airflow
resource "google_service_account_iam_member" "airflow_vm_token_creator" {
  service_account_id = google_service_account.airflow.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.airflow.email}"
}
