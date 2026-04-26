terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state em bucket GCS — ADR-08
  # O bucket deve ser criado manualmente antes do primeiro terraform init:
  #   gcloud storage buckets create gs://<BUCKET_NAME> \
  #     --project=<PROJECT_ID> --location=US --uniform-bucket-level-access
  #
  # Inicializar com configuração parcial de backend:
  #   terraform init -backend-config="bucket=<BUCKET_NAME>"
  backend "gcs" {
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
