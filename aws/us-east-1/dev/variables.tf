variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 2
}

variable "desired_nodes" {
  type    = number
  default = 1
}

variable "cilium_version" {
  type    = string
  default = "1.16.0"
}

variable "school_db_password" {
  description = "Master password for school RDS PostgreSQL"
  type        = string
  sensitive   = true
}
