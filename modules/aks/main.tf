# ─────────────────────────────────────────────────────────────
# Module: AKS with Cilium CNI
#
# - Creates Resource Group + VNet
# - Provisions AKS cluster with network-plugin=none
#   (no Azure CNI — leaves networking to Cilium)
# - Installs Cilium via Helm
# ─────────────────────────────────────────────────────────────

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ─── Resource Group ───────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.cluster_name}"
  location = var.location
  tags     = var.tags
}

# ─── Virtual Network ──────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.node_subnet_cidr]
}

# ─── AKS Cluster ─────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.nodes.id
    os_disk_size_gb = 50
  }

  identity {
    type = "SystemAssigned"
  }

  # network-plugin=none — Cilium manages all networking
  network_profile {
    network_plugin = "none"
    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  tags = var.tags
}

# ─── Helm Provider ────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

# ─── Cilium ───────────────────────────────────────────────────
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set { name = "kubeProxyReplacement"; value = "true" }
  set { name = "azure.enabled";        value = "true" }
  set { name = "ipam.mode";            value = "azure" }

  set {
    name  = "k8sServiceHost"
    value = trimprefix(azurerm_kubernetes_cluster.main.kube_config[0].host, "https://")
  }

  set { name = "k8sServicePort"; value = "443" }
}
