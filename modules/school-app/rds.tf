# ─── Security Group ───────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "school-rds-${var.environment}"
  description = "Allow PostgreSQL access from Lambda and local dev"

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

  publicly_accessible    = true       # For dev — Lambda outside VPC needs this
  skip_final_snapshot    = true       # Dev — no snapshot on destroy
  deletion_protection    = false

  vpc_security_group_ids = [aws_security_group.rds.id]

  tags = merge(var.tags, { Name = "school-${var.environment}" })
}
