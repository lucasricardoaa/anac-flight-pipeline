variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região GCP para os recursos"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona GCP para a VM"
  type        = string
  default     = "us-central1-a"
}

variable "ssh_source_ranges" {
  description = "CIDRs autorizados para SSH na VM do Airflow. Recomenda-se restringir ao IP da máquina de desenvolvimento."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "webserver_source_ranges" {
  description = "CIDRs autorizados para acesso ao Airflow webserver (porta 8080). Recomenda-se restringir ao IP da máquina de desenvolvimento."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
