terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "aws-terraform-state-497041484428"
    key            = "aws/us-east-1/dev/terraform.tfstate"
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

# ─── EKS Cluster ─────────────────────────────────────────────
module "eks" {
  source = "../../../modules/eks"

  cluster_name       = "eks-${var.environment}-us-east-1"
  region             = var.region
  environment        = var.environment
  kubernetes_version = var.kubernetes_version

  availability_zones   = ["us-east-1a", "us-east-1b"]
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

  node_instance_type = var.node_instance_type
  min_nodes          = var.min_nodes
  max_nodes          = var.max_nodes
  desired_nodes      = var.desired_nodes

  tags = {
    environment = var.environment
    cloud       = "aws"
    region      = var.region
    managed_by  = "terraform"
  }
}
