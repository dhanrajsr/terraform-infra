# ─────────────────────────────────────────────────────────────
# Bootstrap: Azure OIDC + Blob Storage State Backend
#
# Run once manually:
#   cd bootstrap/azure
#   terraform init && terraform apply
#
# This creates:
#   - App Registration + Service Principal
#   - Federated Identity Credentials (OIDC) for GitHub Actions
#   - Contributor role assignment on subscription
#   - Storage Account + Container for Terraform remote state
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# ─── App Registration ─────────────────────────────────────────
resource "azuread_application" "github_actions" {
  display_name = "github-actions-terraform"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# ─── Federated Identity Credentials (OIDC) ───────────────────
# For pushes to main
resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

# For pull requests
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-pr"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

# For workflow_dispatch (manual runs from any ref)
resource "azuread_application_federated_identity_credential" "environment" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:environment:${var.github_environment}"
}

# ─── Role Assignment ─────────────────────────────────────────
resource "azurerm_role_assignment" "github_actions" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# ─── Resource Group for State Storage ────────────────────────
resource "azurerm_resource_group" "terraform_state" {
  name     = "rg-terraform-state"
  location = var.location
}

# ─── Storage Account for Terraform State ─────────────────────
resource "azurerm_storage_account" "terraform_state" {
  name                     = "${replace(var.github_org, "-", "")}tfstate"
  resource_group_name      = azurerm_resource_group.terraform_state.name
  location                 = azurerm_resource_group.terraform_state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"
}
