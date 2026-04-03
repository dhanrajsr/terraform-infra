variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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
