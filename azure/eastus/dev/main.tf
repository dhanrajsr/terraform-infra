terraform {
  required_version = ">= 1.6"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "dhanrajsrtfstate"   # update after bootstrap
    container_name       = "tfstate"
    key                  = "azure/eastus/dev/terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "aks" {
  source = "../../../modules/aks"

  cluster_name       = "aks-${var.environment}-eastus"
  location           = var.location
  environment        = var.environment
  kubernetes_version = var.kubernetes_version

  node_count   = var.node_count
  node_vm_size = var.node_vm_size

  vnet_cidr        = "10.1.0.0/16"
  node_subnet_cidr = "10.1.0.0/22"
  pod_cidr         = "10.244.0.0/16"
  service_cidr     = "10.96.0.0/16"
  dns_service_ip   = "10.96.0.10"

  cilium_version = var.cilium_version

  tags = {
    environment = var.environment
    cloud       = "azure"
    region      = var.location
    managed_by  = "terraform"
  }
}
