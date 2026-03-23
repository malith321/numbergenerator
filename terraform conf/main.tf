terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── VPC & Networking ──────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

# ── Security Groups ───────────────────────────────────────────────────────────
module "security" {
  source = "./modules/security"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

# ── RDS PostgreSQL ────────────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project            = var.project
  environment        = var.environment
  db_subnet_group    = module.vpc.db_subnet_group_name
  security_group_id  = module.security.sg_db_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
}

# ── ECS Fargate (API) ─────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  project           = var.project
  environment       = var.environment
  aws_region        = var.aws_region
  private_subnet_id = module.vpc.private_subnet_a_id
  security_group_id = module.security.sg_api_id
  db_url            = "postgresql://${var.db_username}:${var.db_password}@${module.rds.db_endpoint}:5432/${var.db_name}"
  ecr_image_url     = var.ecr_image_url
}

# ── EC2 VPN Gateway ───────────────────────────────────────────────────────────
module "vpn" {
  source = "./modules/vpn"

  project           = var.project
  environment       = var.environment
  public_subnet_id  = module.vpc.public_subnet_id
  security_group_id = module.security.sg_vpn_id
  key_pair_name     = var.key_pair_name
  instance_type     = var.vpn_instance_type
}

# ── IAM Users & Groups ────────────────────────────────────────────────────────
module "iam" {
  source = "./modules/iam"

  project          = var.project
  environment      = var.environment
  aws_region       = var.aws_region
  developer_users  = var.developer_users
  readonly_users   = var.readonly_users
}
