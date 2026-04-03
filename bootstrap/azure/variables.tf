variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
  default     = "dhanrajsr"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "terraform-infra"
}

variable "github_environment" {
  description = "GitHub environment name used in workflow_dispatch federated credential"
  type        = string
  default     = "prod"
}
