# ─────────────────────────────────────────────────────────────
# Bootstrap: GCP Workload Identity Federation + GCS State Backend
#
# Run once manually:
#   cd bootstrap/gcp
#   terraform init && terraform apply
#
# This creates:
#   - Workload Identity Pool + Provider for GitHub Actions OIDC
#   - Service Account with required roles
#   - GCS bucket for Terraform remote state
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
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

# ─── Enable Required APIs ─────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ─── Workload Identity Pool ───────────────────────────────────
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

# ─── Workload Identity Pool Provider ─────────────────────────
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Only allow tokens from this specific repo
  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"
}

# ─── Service Account for GitHub Actions ──────────────────────
resource "google_service_account" "github_actions" {
  account_id   = "github-actions-terraform"
  display_name = "GitHub Actions Terraform"
  depends_on   = [google_project_service.apis]
}

# ─── Allow GitHub repo to impersonate the Service Account ────
resource "google_service_account_iam_member" "github_actions_wif" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# ─── Grant Roles to Service Account ──────────────────────────
resource "google_project_iam_member" "github_actions" {
  for_each = toset([
    "roles/container.admin",
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# ─── GCS Bucket for Terraform State ──────────────────────────
resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_id}-terraform-state"
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.apis]
}
