# =============================================================================
# Buckets GCS — ADR-07 (Arquitetura Medalhão), ADR-08
# =============================================================================

resource "google_storage_bucket" "bronze" {
  name                        = "${var.project_id}-bronze"
  location                    = "US"
  uniform_bucket_level_access = true

  # Bronze é fonte da verdade imutável (ADR-07) — sem lifecycle rules de expiração
  # para dados ingeridos. force_destroy=false protege contra remoção acidental.
  force_destroy = false
}

resource "google_storage_bucket" "silver" {
  name                        = "${var.project_id}-silver"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = false

  # [VERIFICAR #11] — lifecycle rule apenas para objetos temporários de jobs Spark.
  # Dados processados da camada Silver não expiram.
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["_spark_staging/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "gold" {
  name                        = "${var.project_id}-gold"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = false

  # [VERIFICAR #11] — mesma regra de limpeza de staging que a camada Silver.
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["_spark_staging/"]
    }
    action {
      type = "Delete"
    }
  }
}

# =============================================================================
# VM Compute Engine — ADR-06 (e2-medium + Docker Compose)
# =============================================================================

resource "google_compute_address" "airflow" {
  name   = "airflow-ip"
  region = var.region
}

resource "google_compute_instance" "airflow" {
  name         = "airflow-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  tags = ["airflow"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.airflow.address
    }
  }

  service_account {
    email  = google_service_account.airflow.email
    scopes = ["cloud-platform"]
  }

  # [VERIFICAR #10] — bootstrap do Docker como metadata_startup_script.
  # Executado automaticamente pelo GCP na primeira inicialização da VM.
  # Logs disponíveis em: /var/log/syslog (procurar por "startup-script")
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    # Instalar Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Adicionar usuário padrão ao grupo docker
    usermod -aG docker ubuntu
  EOT

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# =============================================================================
# Firewall — ADR-08 (VPC default com firewall rules explícitas)
# =============================================================================

resource "google_compute_firewall" "airflow_webserver" {
  name    = "allow-airflow-webserver"
  network = "default"

  description = "Permite acesso ao Airflow webserver (porta 8080). Restringir source_ranges ao IP da máquina de desenvolvimento em produção."

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = var.webserver_source_ranges
  target_tags   = ["airflow"]
}

resource "google_compute_firewall" "airflow_ssh" {
  name    = "allow-airflow-ssh"
  network = "default"

  description = "Permite SSH na VM do Airflow. Restringir source_ranges ao IP da máquina de desenvolvimento."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["airflow"]
}

# =============================================================================
# Secret Manager — ADR-08
# Os valores placeholder devem ser substituídos manualmente após o terraform apply:
#   gcloud secrets versions add <SECRET_NAME> --data-file=-
# =============================================================================

resource "google_secret_manager_secret" "airflow_fernet_key" {
  secret_id = "airflow-fernet-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "airflow_fernet_key" {
  secret      = google_secret_manager_secret.airflow_fernet_key.id
  secret_data = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret" "airflow_db_password" {
  secret_id = "airflow-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "airflow_db_password" {
  secret      = google_secret_manager_secret.airflow_db_password.id
  secret_data = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_data]
  }
}
