variable "environment" {
  description = "Environment name (dev/sit/uat/prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "schooldb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "school"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "lambda_jar_bucket" {
  description = "S3 bucket name where the Lambda JAR is uploaded"
  type        = string
}

variable "lambda_jar_key" {
  description = "S3 object key of the Lambda JAR"
  type        = string
  default     = "school-api-lambda.jar"
}

variable "custom_domain" {
  description = "Custom domain for API Gateway (e.g. school-api.devopscab.com). Leave empty to skip."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
