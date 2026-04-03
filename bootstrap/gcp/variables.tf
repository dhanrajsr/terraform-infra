variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "gen-lang-client-0110201077"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
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
