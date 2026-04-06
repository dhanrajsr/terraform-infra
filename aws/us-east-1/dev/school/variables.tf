variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "school_db_password" {
  description = "Master password for school RDS PostgreSQL"
  type        = string
  sensitive   = true
}
