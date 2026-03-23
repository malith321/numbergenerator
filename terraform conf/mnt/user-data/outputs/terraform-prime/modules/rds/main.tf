# ── RDS PostgreSQL Instance ───────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = var.db_subnet_group
  vpc_security_group_ids = [var.security_group_id]

  publicly_accessible     = false
  skip_final_snapshot     = true   # set false in production
  backup_retention_period = 7
  deletion_protection     = false  # set true in production

  tags = {
    Name        = "${var.project}-db"
    Environment = var.environment
    Project     = var.project
  }
}
