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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
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

# ─── Helm Provider (root module — providers cannot live in child modules) ─────
data "aws_eks_cluster_auth" "main" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# ─── Cilium ───────────────────────────────────────────────────
resource "helm_release" "cilium" {
  depends_on = [module.eks]
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set {
    name  = "eni.enabled"
    value = "true"
  }
  set {
    name  = "ipam.mode"
    value = "eni"
  }
  set {
    name  = "egressMasqueradeInterfaces"
    value = "eth0"
  }
  set {
    name  = "tunnel"
    value = "disabled"
  }
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }
  set {
    name  = "k8sServiceHost"
    value = module.eks.cluster_endpoint
  }
  set {
    name  = "k8sServicePort"
    value = "443"
  }
}
