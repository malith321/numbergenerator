# ── sg-vpn: WireGuard gateway ─────────────────────────────────────────────────
resource "aws_security_group" "vpn" {
  name        = "${var.project}-sg-vpn"
  description = "WireGuard VPN gateway — UDP 51820 inbound only"
  vpc_id      = var.vpc_id

  ingress {
    description = "WireGuard VPN handshake"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for management (restrict to your IP in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-vpn", Environment = var.environment }
}

# ── sg-api: FastAPI service ───────────────────────────────────────────────────
resource "aws_security_group" "api" {
  name        = "${var.project}-sg-api"
  description = "Prime API — port 8000 from VPN only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "API access from VPN gateway only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-api", Environment = var.environment }
}

# ── sg-db: PostgreSQL ─────────────────────────────────────────────────────────
resource "aws_security_group" "db" {
  name        = "${var.project}-sg-db"
  description = "PostgreSQL — port 5432 from API only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from API only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-db", Environment = var.environment }
}
