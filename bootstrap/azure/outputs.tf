output "client_id" {
  description = "Set as AZURE_CLIENT_ID GitHub Secret"
  value       = azuread_application.github_actions.client_id
}

output "tenant_id" {
  description = "Set as AZURE_TENANT_ID GitHub Secret"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Set as AZURE_SUBSCRIPTION_ID GitHub Secret"
  value       = data.azurerm_subscription.current.subscription_id
}

output "storage_account_name" {
  description = "Azure Storage Account name for Terraform state backend"
  value       = azurerm_storage_account.terraform_state.name
}

output "storage_container_name" {
  description = "Azure Storage Container name for Terraform state backend"
  value       = azurerm_storage_container.terraform_state.name
}
