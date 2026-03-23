variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name — used in all resource names and tags"
  type        = string
  default     = "prime"
}

variable "environment" {
  description = "Environment name (dev / staging / prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ── Database ──────────────────────────────────────────────────────────────────
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "prime_db"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "prime_user"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

# ── ECS / Container ───────────────────────────────────────────────────────────
variable "ecr_image_url" {
  description = "Full ECR image URL (ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/prime-api:latest)"
  type        = string
}

# ── VPN ───────────────────────────────────────────────────────────────────────
variable "key_pair_name" {
  description = "Name of the EC2 key pair for SSH access to the VPN instance"
  type        = string
}

variable "vpn_instance_type" {
  description = "EC2 instance type for the VPN gateway"
  type        = string
  default     = "t3.micro"
}

# ── IAM Users ─────────────────────────────────────────────────────────────────
variable "developer_users" {
  description = "List of IAM usernames to add to the developers group"
  type        = list(string)
  default     = []
}

variable "readonly_users" {
  description = "List of IAM usernames to add to the readonly group"
  type        = list(string)
  default     = []
}
