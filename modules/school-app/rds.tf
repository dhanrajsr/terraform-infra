# ─── EKS VPC + Private Subnets ───────────────────────────────
data "aws_vpc" "eks" {
  filter {
    name   = "tag:Name"
    values = ["eks-${var.environment}-us-east-1-vpc"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks.id]
  }
  filter {
    name   = "tag:Name"
    values = ["eks-${var.environment}-us-east-1-vpc-public-*"]
  }
}

# ─── DB Subnet Group ──────────────────────────────────────────
resource "aws_db_subnet_group" "school" {
  name       = "school-${var.environment}"
  subnet_ids = data.aws_subnets.public.ids

  tags = merge(var.tags, { Name = "school-${var.environment}" })
}

# ─── Security Group ───────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "school-rds-${var.environment}"
  description = "Allow PostgreSQL access from Lambda and local dev"
  vpc_id      = data.aws_vpc.eks.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # Open for dev — restrict in prod
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "school-rds-${var.environment}" })
}

# ─── RDS PostgreSQL ───────────────────────────────────────────
resource "aws_db_instance" "school" {
  identifier        = "school-${var.environment}"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"   # Free tier eligible
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.school.name
  publicly_accessible    = true       # For dev — Lambda outside VPC needs this
  skip_final_snapshot    = true       # Dev — no snapshot on destroy
  deletion_protection    = false

  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = merge(var.tags, { Name = "school-${var.environment}" })
}
