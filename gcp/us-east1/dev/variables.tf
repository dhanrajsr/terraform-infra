variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "cilium_version" {
  type    = string
  default = "1.16.0"
}
