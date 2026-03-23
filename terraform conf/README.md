# Prime Service — Terraform (AWS)

Creates all AWS infrastructure for the Prime Number Generator Service in one command.

## What gets created

| Resource | Description |
|---|---|
| VPC + subnets | 1 public subnet (VPN), 2 private subnets (API + DB) |
| Internet Gateway | Routes public traffic to VPN gateway |
| Security Groups | sg-vpn, sg-api, sg-db with least-privilege rules |
| EC2 (t3.micro) | WireGuard VPN gateway — auto-configured on boot |
| Elastic IP | Stable public IP for the VPN endpoint |
| ECS Fargate | Runs the prime_api container |
| ECR | Private Docker image registry |
| RDS PostgreSQL 16 | Managed database in private subnet |
| CloudWatch Logs | API container logs with 30-day retention |
| IAM Groups | prime-developers and prime-readonly |
| IAM Users | One per name in developer_users / readonly_users |

## Project structure

```
terraform-prime/
├── main.tf                    # Root — wires all modules together
├── variables.tf               # All input variables
├── outputs.tf                 # Useful outputs after apply
├── terraform.tfvars.example   # Copy to terraform.tfvars and fill in
├── deploy.sh                  # Helper: build image + terraform apply
├── .gitignore
└── modules/
    ├── vpc/       # VPC, subnets, IGW, route tables, DB subnet group
    ├── security/  # Security groups (sg-vpn, sg-api, sg-db)
    ├── rds/       # RDS PostgreSQL instance
    ├── ecs/       # ECR repo, ECS cluster, task definition, service
    ├── vpn/       # EC2 instance + Elastic IP + WireGuard bootstrap
    └── iam/       # Groups, policies, users
```

## Prerequisites

1. **Terraform >= 1.6** — https://developer.hashicorp.com/terraform/install
2. **AWS CLI configured** — `aws configure`
3. **Docker Desktop running** (for building the image)
4. **An EC2 key pair** created in AWS console → EC2 → Key Pairs

## Step-by-step deployment

### 1 — Install Terraform (Windows)

```powershell
winget install Hashicorp.Terraform
terraform -version
```

### 2 — Create your tfvars file

```powershell
copy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Fill in your values:

```hcl
aws_region    = "eu-west-1"
project       = "prime"
environment   = "dev"
db_password   = "ChangeMe123!"
key_pair_name = "my-key-pair"
ecr_image_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/prime-api:latest"

developer_users = ["alice"]
readonly_users  = ["bob"]
```

### 3 — Create ECR repo and push your image first

Terraform needs the ECR repo to exist before the ECS task definition is registered. Run this once:

```powershell
# Get your account ID
aws sts get-caller-identity --query Account --output text

# Create ECR repo
aws ecr create-repository --repository-name prime-api --region eu-west-1

# Login, build, push
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$ECR_URL = "$ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com"

aws ecr get-login-password --region eu-west-1 | `
  docker login --username AWS --password-stdin $ECR_URL

docker build -t prime-api ../
docker tag prime-api:latest "$ECR_URL/prime-api:latest"
docker push "$ECR_URL/prime-api:latest"
```

Update `ecr_image_url` in `terraform.tfvars` with the full URL.

### 4 — Initialise Terraform

```powershell
terraform init
```

### 5 — Preview what will be created

```powershell
terraform plan
```

You'll see a list of every resource Terraform will create. Review it before applying.

### 6 — Deploy everything

```powershell
terraform apply
```

Type `yes` when prompted. Takes about **8–12 minutes** (RDS takes the longest).

### 7 — Check the outputs

```powershell
terraform output
```

You'll see:

```
vpn_public_ip      = "1.2.3.4"
ecr_repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/prime-api"
ssh_command        = "ssh -i my-key-pair.pem ec2-user@1.2.3.4"
developer_group    = "prime-developers"
readonly_group     = "prime-readonly"
```

### 8 — Configure WireGuard client

SSH into the VPN instance and get the server public key:

```powershell
ssh -i my-key-pair.pem ec2-user@VPN_PUBLIC_IP
cat ~/server_public.key
```

Create a WireGuard peer config on the server for your user:

```bash
# On the EC2 instance
wg genkey | tee client_private.key | wg pubkey > client_public.key

sudo wg set wg0 peer $(cat client_public.key) allowed-ips 10.8.0.2/32

cat << EOF > client.conf
[Interface]
PrivateKey = $(cat client_private.key)
Address = 10.8.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat ~/server_public.key)
Endpoint = VPN_PUBLIC_IP:51820
AllowedIPs = 10.0.0.0/16
PersistentKeepalive = 25
EOF

cat client.conf
```

Copy the `client.conf` output, import into WireGuard app, and activate.

### 9 — Test the API

With VPN connected, get the ECS task private IP:

```powershell
$TASK = aws ecs list-tasks --cluster prime-cluster `
  --service-name prime-api-service --query 'taskArns[0]' --output text

aws ecs describe-tasks --cluster prime-cluster --tasks $TASK `
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value'
```

Then test:

```powershell
curl.exe http://ECS_PRIVATE_IP:8000/health
# {"status":"ok"}
```

## Updating the API (redeploy)

After making code changes, rebuild and push the image, then force a new ECS deployment:

```powershell
# Push new image
docker build -t prime-api ../
docker tag prime-api:latest "$ECR_URL/prime-api:latest"
docker push "$ECR_URL/prime-api:latest"

# Force ECS to pull the new image
aws ecs update-service --cluster prime-cluster `
  --service prime-api-service --force-new-deployment
```

## Destroy everything

```powershell
terraform destroy
```

Type `yes` to confirm. This removes all resources and stops all charges.

## Troubleshooting

| Problem | Fix |
|---|---|
| `terraform init` fails | Check internet connection and that AWS CLI is configured |
| `Error: creating ECR repository: already exists` | Repo already exists — just push your image and continue |
| RDS times out during apply | Normal — RDS takes 8-10 min. Let it run. |
| ECS service stuck at 0 running | Check CloudWatch logs: `aws logs tail /ecs/prime-api --follow` |
| VPN not routing to ECS | SSH into EC2 and run `sudo wg show` to verify the tunnel is active |
| `terraform destroy` fails on VPC | ECS service must stop first — run `terraform destroy -target=module.ecs` first |
