# ─────────────────────────────────────────────────────────────
# Module: EKS
#
# - Creates VPC with public/private subnets
# - Provisions EKS cluster (CoreDNS only — no aws-node/kube-proxy)
# - Disables AWS VPC CNI (aws-node daemonset) so Cilium can own networking
#
# NOTE: Cilium is installed in the root module (aws/us-east-1/<env>/main.tf)
# because provider blocks cannot be configured inside child modules.
# ─────────────────────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

  # CoreDNS only — Cilium replaces aws-node (VPC CNI) and kube-proxy
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

  # Grants cluster-admin to whichever IAM identity runs terraform apply
  # Works for both GitHub Actions (OIDC role) and local (root/IAM user)
  enable_cluster_creator_admin_permissions = true

  # Additional IAM principals with cluster-admin access
  access_entries = {
    for arn in var.admin_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  tags = var.tags
}

# ─── Disable aws-node DaemonSet ───────────────────────────────
# Replaces aws-node image with a no-op so Cilium owns networking
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
