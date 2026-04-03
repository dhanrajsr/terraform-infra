terraform {
  required_version = ">= 1.6"

  backend "gcs" {
    bucket = "<PROJECT_ID>-terraform-state"   # update after bootstrap
    prefix = "gcp/us-east1/dev"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gke" {
  source = "../../../modules/gke"

  cluster_name       = "gke-${var.environment}-us-east1"
  project_id         = var.project_id
  region             = var.region
  environment        = var.environment
  kubernetes_version = var.kubernetes_version

  node_count        = var.node_count
  node_machine_type = var.node_machine_type

  node_subnet_cidr = "10.2.0.0/22"
  pod_cidr         = "10.100.0.0/16"
  service_cidr     = "10.96.0.0/16"

  cilium_version = var.cilium_version
}
