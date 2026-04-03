# ─────────────────────────────────────────────────────────────
# Module: GKE with Cilium CNI
#
# - Creates VPC + subnet
# - Provisions GKE cluster with:
#     datapath_provider = LEGACY_DATAPATH  (disables GKE Dataplane V2)
#     networking_mode   = VPC_NATIVE
# - Installs Cilium via Helm
# ─────────────────────────────────────────────────────────────

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── VPC ─────────────────────────────────────────────────────
resource "google_compute_network" "main" {
  name                    = "vpc-${var.cluster_name}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "nodes" {
  name          = "snet-${var.cluster_name}-nodes"
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.node_subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }
}

# ─── GKE Cluster ─────────────────────────────────────────────
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.region

  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.nodes.id

  # Disable default node pool — we manage it separately
  remove_default_node_pool = true
  initial_node_count       = 1

  min_master_version = var.kubernetes_version

  # VPC-native mode required for Cilium
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # LEGACY_DATAPATH disables GKE Dataplane V2 (eBPF)
  # Required to allow Cilium to own the dataplane
  datapath_provider = "LEGACY_DATAPATH"

  # Disable network policy — Cilium handles it
  network_policy {
    enabled = false
  }

  addons_config {
    network_policy_config {
      disabled = true
    }
  }
}

# ─── Node Pool ───────────────────────────────────────────────
resource "google_container_node_pool" "main" {
  name     = "main"
  cluster  = google_container_cluster.main.id
  location = var.region

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = 50
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
    }
  }
}

# ─── Helm Provider ────────────────────────────────────────────
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  }
}

# ─── Cilium ───────────────────────────────────────────────────
resource "helm_release" "cilium" {
  depends_on = [google_container_node_pool.main]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }
  set {
    name  = "gke.enabled"
    value = "true"
  }
  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }
  set {
    name  = "k8sServiceHost"
    value = google_container_cluster.main.endpoint
  }
  set {
    name  = "k8sServicePort"
    value = "443"
  }
}
