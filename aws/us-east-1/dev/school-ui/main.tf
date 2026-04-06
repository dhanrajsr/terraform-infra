terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "aws-terraform-state-497041484428"
    key            = "aws/us-east-1/dev/school-ui/terraform.tfstate"
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
  region = "us-east-1"
}

module "school_ui" {
  source = "../../../../modules/school-ui"

  environment = "dev"
  account_id  = "497041484428"

  tags = {
    environment = "dev"
    cloud       = "aws"
    region      = "us-east-1"
    managed_by  = "terraform"
    app         = "school-ui"
  }
}

output "cloudfront_url" {
  value = module.school_ui.cloudfront_url
}

output "s3_bucket" {
  value = module.school_ui.s3_bucket
}
