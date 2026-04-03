variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
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

variable "node_machine_type" {
  description = "GCP machine type for worker nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "node_subnet_cidr" {
  description = "Node subnet CIDR"
  type        = string
  default     = "10.2.0.0/22"
}

variable "pod_cidr" {
  description = "Pod secondary range CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "service_cidr" {
  description = "Service secondary range CIDR"
  type        = string
  default     = "10.96.0.0/16"
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.16.0"
}
