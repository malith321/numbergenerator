output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpn_public_ip" {
  description = "Public IP of the WireGuard VPN gateway — use this as the WireGuard Endpoint"
  value       = module.vpn.public_ip
}

output "api_private_ip" {
  description = "Private IP of the ECS Fargate task — access this via VPN at port 8000"
  value       = "Connect via VPN then check ECS task IP: aws ecs describe-tasks --cluster ${var.project}-cluster"
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "ecr_repository_url" {
  description = "ECR repository URL — push your Docker image here"
  value       = module.ecs.ecr_repository_url
}

output "ssh_command" {
  description = "SSH command to connect to the VPN gateway EC2 instance"
  value       = "ssh -i ${var.key_pair_name}.pem ec2-user@${module.vpn.public_ip}"
}

output "api_health_check" {
  description = "API health check URL (requires VPN connected)"
  value       = "http://<ECS_TASK_PRIVATE_IP>:8000/health"
}

output "developer_group" {
  description = "IAM group for developers"
  value       = module.iam.developer_group_name
}

output "readonly_group" {
  description = "IAM group for readonly users"
  value       = module.iam.readonly_group_name
}
