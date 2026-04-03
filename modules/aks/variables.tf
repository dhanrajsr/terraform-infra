variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment (dev/sit/uat/prod)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

variable "node_vm_size" {
  description = "Azure VM size for worker nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
  default     = "10.1.0.0/16"
}

variable "node_subnet_cidr" {
  description = "Subnet CIDR for nodes"
  type        = string
  default     = "10.1.0.0/22"
}

variable "pod_cidr" {
  description = "Pod CIDR (managed by Cilium)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR"
  type        = string
  default     = "10.96.0.0/16"
}

variable "dns_service_ip" {
  description = "DNS service IP (must be within service_cidr)"
  type        = string
  default     = "10.96.0.10"
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.16.0"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
