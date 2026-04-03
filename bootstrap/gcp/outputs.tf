output "workload_identity_provider" {
  description = "Set as GCP_WORKLOAD_IDENTITY_PROVIDER GitHub Secret"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "Set as GCP_SERVICE_ACCOUNT GitHub Secret"
  value       = google_service_account.github_actions.email
}

output "state_bucket" {
  description = "GCS bucket name for Terraform state backend"
  value       = google_storage_bucket.terraform_state.name
}
