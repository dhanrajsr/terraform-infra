# ─────────────────────────────────────────────────────────────
# Module: EKS with Cilium CNI
#
# - Creates VPC with public/private subnets
# - Provisions EKS cluster (no aws-node / kube-proxy addons)
# - Disables AWS VPC CNI (aws-node daemonset)
# - Installs Cilium via Helm in ENI mode with kube-proxy replacement
# ─────────────────────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ─── VPC ─────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "prod"
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"
  }

  tags = var.tags
}

# ─── EKS Cluster ─────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Only CoreDNS — no aws-node (VPC CNI) or kube-proxy
  # Cilium replaces both
  cluster_addons = {
    coredns = { most_recent = true }
  }

  eks_managed_node_groups = {
    main = {
      instance_types = [var.node_instance_type]
      min_size       = var.min_nodes
      max_size       = var.max_nodes
      desired_size   = var.desired_nodes

      labels = {
        environment = var.environment
      }
    }
  }

  tags = var.tags
}

# ─── Disable aws-node DaemonSet ───────────────────────────────
# Replaces aws-node container image with a no-op image
# so Cilium can take full ownership of networking
resource "null_resource" "disable_aws_node" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}
      kubectl -n kube-system set image daemonset/aws-node \
        aws-node=public.ecr.aws/amazonlinux/amazonlinux:2 || true
    EOT
  }
}

# ─── Helm Provider (authenticated via kubeconfig) ────────────
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

# ─── Cilium ───────────────────────────────────────────────────
resource "helm_release" "cilium" {
  depends_on = [null_resource.disable_aws_node]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set { name = "eni.enabled";                value = "true" }
  set { name = "ipam.mode";                  value = "eni" }
  set { name = "egressMasqueradeInterfaces"; value = "eth0" }
  set { name = "tunnel";                     value = "disabled" }
  set { name = "kubeProxyReplacement";       value = "true" }
  set { name = "k8sServiceHost";             value = module.eks.cluster_endpoint }
  set { name = "k8sServicePort";             value = "443" }
}
