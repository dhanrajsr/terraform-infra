terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "aws-terraform-state-497041484428"
    key            = "aws/us-east-1/dev/school/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ─── School App (Lambda + RDS + API Gateway) ─────────────────
module "school_app" {
  source = "../../../../modules/school-app"

  environment       = var.environment
  region            = var.region
  db_password       = var.school_db_password
  lambda_jar_bucket = "school-lambda-jar-497041484428-${var.environment}"
  custom_domain     = "school-api.devopscab.com"
  ui_domain         = "school.devopscab.com"

  tags = {
    environment = var.environment
    cloud       = "aws"
    region      = var.region
    managed_by  = "terraform"
    app         = "school"
  }
}
