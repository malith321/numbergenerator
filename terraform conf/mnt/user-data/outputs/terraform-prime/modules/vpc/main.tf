# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
  }
}

# ── Public Subnet (VPN gateway lives here) ────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)   # 10.0.1.0/24
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project}-public"
    Environment = var.environment
    Type        = "public"
  }
}

# ── Private Subnet A (API + DB primary AZ) ────────────────────────────────────
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)   # 10.0.2.0/24
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project}-private-a"
    Environment = var.environment
    Type        = "private"
  }
}

# ── Private Subnet B (RDS requires 2 AZs) ────────────────────────────────────
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)   # 10.0.3.0/24
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project}-private-b"
    Environment = var.environment
    Type        = "private"
  }
}

# ── Public Route Table ────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ── RDS Subnet Group ──────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name        = "${var.project}-db-subnet-group"
    Environment = var.environment
  }
}
