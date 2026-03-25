# Prime Number Generator Service

A production-ready HTTP microservice that generates prime numbers over a user-supplied range, records every execution in PostgreSQL, runs as isolated Docker containers on a private network, and is accessible only through a WireGuard VPN.

---

## Table of Contents

- [Project Structure](#project-structure)
- [Task 1 — Prime Number Service](#task-1--prime-number-service)
  - [Algorithm](#algorithm)
  - [API Reference](#api-reference)
  - [Running Locally](#running-locally)
  - [CLI Client](#cli-client)
  - [Running Tests](#running-tests)
- [Task 2 — Private Network & VPN](#task-2--private-network--vpn)
  - [Architecture](#architecture)
  - [Windows Setup](#windows-setup)
  - [Connecting a Phone](#connecting-a-phone)

---

## Project Structure

```
prime-service/
├── app/
│   ├── __init__.py
│   ├── main.py          # FastAPI app, route handlers
│   ├── primes.py        # Segmented Sieve of Eratosthenes
│   └── database.py      # asyncpg pool, DDL, queries
├── tests/
│   ├── __init__.py
│   └── test_primes.py   # 18 unit tests
├── wireguard/
│   └── config/          # WireGuard peer configs (auto-generated)
├── cli.py               # Zero-dependency CLI client
├── Dockerfile           # Multi-stage image
├── docker-compose.yml   # API + PostgreSQL + WireGuard
├── setup-vpn.sh         # VPN setup helper script
└── requirements.txt
```

---

# Task 1 — Prime Number Service

## Algorithm

The service uses the **Segmented Sieve of Eratosthenes**.

A classic sieve allocates a boolean array of size `end` — wasteful for large ranges. The segmented variant sieves fixed **32 KB windows** (L1-cache-friendly), using only the "small primes" up to √end. An additional optimisation: the inner loop only tracks **odd numbers**, halving both array size and work.

- **Time complexity:** O(n log log n)
- **Memory:** O(√n) peak — far better than a plain sieve
- **Range cap:** 10,000,000 (enforced by the API)

## API Reference

Interactive docs available at `http://localhost:8000/docs` once running.

### `GET /primes`

Returns all prime numbers in `[start, end]`.

| Parameter | Type | Required | Constraints |
|-----------|------|----------|-------------|
| `start` | integer | Yes | >= 0 |
| `end` | integer | Yes | >= 0, <= 10,000,000 |

**Example:**
```bash
curl "http://localhost:8000/primes?start=1&end=50"
```

**Response:**
```json
{
  "range": { "start": 1, "end": 50 },
  "prime_count": 15,
  "primes": [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47],
  "elapsed_ms": 0.042
}
```

### `GET /executions`

Returns paginated history of all past queries.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Records per page (1–100) |
| `offset` | integer | 0 | Pagination offset |

### `GET /health`

```json
{ "status": "ok" }
```

## Running Locally

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop) (running)

### Start

```bash
docker compose up -d --build
```

### Verify

```bash
curl http://localhost:8000/health
# {"status":"ok"}

curl "http://localhost:8000/primes?start=1&end=100"
```

### Stop

```bash
docker compose down        # keep database
docker compose down -v     # also wipe database
```

## CLI Client

Zero external dependencies — uses Python stdlib only.

```bash
# Generate primes
python cli.py primes 1 100

# Large range
python cli.py primes 900000 1000000

# View execution history
python cli.py history --limit 10

# Health check
python cli.py health

# Custom host
python cli.py --base-url http://172.20.0.3:8000 primes 1 100
```

**Example output:**
```
──────────────────────────────────────────────────
  Range        : 1 – 100
  Primes found : 25
  Time taken   : 0.038 ms
──────────────────────────────────────────────────
  2  3  5  7  11  13  17  19  23  29
  31  37  41  43  47  53  59  61  67  71
  73  79  83  89  97
```

## Running Tests

```bash
python -m pytest tests/ -v
```

All 18 tests cover correctness, boundary conditions, and known prime-counting values (π(1000) = 168, π(100,000) = 9,592).

---

# Task 2 — Private Network & VPN

## Architecture

```
Internet / External users
        │
        │  UDP 51820 (VPN only)
        ▼
┌──────────────────────────────────────────────┐
│         Private Docker Network               │
│         prime_net (192.168.100.0/24)         │
│                                              │
│  ┌──────────────────┐                        │
│  │  WireGuard VPN   │  192.168.100.2         │
│  │  Gateway         │  ← sole entry point    │
│  └────────┬─────────┘                        │
│           │ VPN tunnel                       │
│           ▼                                  │
│  ┌──────────────────┐                        │
│  │  prime_api       │  192.168.100.3:8000    │
│  │  FastAPI         │  ← no host port        │
│  └────────┬─────────┘                        │
│           │ SQL                              │
│           ▼                                  │
│  ┌──────────────────┐                        │
│  │  prime_db        │  internal only         │
│  │  PostgreSQL      │  ← no host port        │
│  └──────────────────┘                        │
└──────────────────────────────────────────────┘
```

| Security Property | How Enforced |
|---|---|
| DB is private | No `ports:` block — unreachable from host |
| API is private | Bound to `127.0.0.1:8000` — not exposed externally |
| Only VPN users reach API | Windows Firewall blocks port 8000 except from VPN subnet |
| Single ingress point | Only UDP 51820 mapped to host |

## Windows Setup

### Step 1 — Install prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop) — enable **Use WSL 2 based engine**
- [WireGuard for Windows](https://www.wireguard.com/install/)
- [Python](https://www.python.org/downloads/) — check **Add Python to PATH**

### Step 2 — Write the docker-compose.yml

Open PowerShell in your project folder and run:

```powershell
Set-Content -Path "docker-compose.yml" -Value @"
networks:
  prime_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.100.0/24

services:

  db:
    image: postgres:16-alpine
    container_name: prime_db
    restart: unless-stopped
    environment:
      POSTGRES_USER: prime_user
      POSTGRES_PASSWORD: prime_pass
      POSTGRES_DB: prime_db
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - prime_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U prime_user -d prime_db"]
      interval: 5s
      timeout: 5s
      retries: 10

  api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: prime_api
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://prime_user:prime_pass@db:5432/prime_db
      WORKERS: 4
    ports:
      - "127.0.0.1:8000:8000"
    networks:
      prime_net:
        ipv4_address: 192.168.100.3

volumes:
  pgdata:
"@
```

### Step 3 — Start containers

```powershell
docker compose up -d --build
docker ps
# Should show prime_db and prime_api both Up
```

### Step 4 — Set up WireGuard VPN server

1. Open **WireGuard** from system tray
2. Click **Add Tunnel** → **Add empty tunnel**
3. Keep the auto-generated `PrivateKey` line, add these lines below it:

```ini
[Interface]
PrivateKey = (already generated — do not change)
Address = 10.8.0.1/24
ListenPort = 51820
```

4. Name it `wg-server` → **Save** → **Activate**

5. Verify it's running:

```powershell
ipconfig
# Should show adapter "wg-server" with IP 10.8.0.1
```

### Step 5 — Add firewall rules (PowerShell as Administrator)

```powershell
# Block port 8000 from external access
netsh advfirewall firewall add rule name="Block API external" protocol=TCP dir=in localport=8000 action=block

# Allow port 8000 only from VPN subnet
netsh advfirewall firewall add rule name="Allow API via VPN" protocol=TCP dir=in localport=8000 remoteip=10.8.0.0/24 action=allow

# Allow WireGuard UDP handshakes
netsh advfirewall firewall add rule name="WireGuard UDP" protocol=UDP dir=in localport=51820 action=allow
```

### Step 6 — Test

```powershell
curl.exe http://127.0.0.1:8000/health
# {"status":"ok"}

curl.exe "http://127.0.0.1:8000/primes?start=1&end=50"
```

## Connecting a Phone

### On your phone

1. Install **WireGuard** from App Store / Google Play
2. Tap **+** → **Create from scratch**
3. Tap **Generate keypair** — note down the **public key**
4. Fill in:

```
[Interface]
Name:    prime-client
Address: 10.8.0.2/24
DNS:     8.8.8.8
```

### Get your server's public key (Windows PowerShell)

```powershell
& "C:\Program Files\WireGuard\wg.exe" show wg-server public-key
```

### Add phone as peer on Windows

Open WireGuard → Edit `wg-server` → add at the bottom:

```ini
[Peer]
PublicKey = PASTE_PHONE_PUBLIC_KEY_HERE
AllowedIPs = 10.8.0.2/32
```

**Deactivate → Activate** to apply.

### Complete phone config

Back on your phone, paste the server public key into the Peer section:

```
[Peer]
Public key:  (Windows server public key)
Endpoint:    YOUR_PUBLIC_IP:51820
Allowed IPs: 0.0.0.0/0
```

Find your public IP:
```powershell
curl.exe https://api.ipify.org
```

### Set up port forwarding on your router

1. Go to `http://192.168.0.1` (your router admin page)
2. Find **Port Forwarding**
3. Add rule: UDP port 51820 → 192.168.0.206 (your PC's local IP)

### Test from phone

Turn off WiFi on phone (use mobile data), activate VPN, then open browser:
```
http://127.0.0.1:8000/health
http://127.0.0.1:8000/docs
```

---

WS Cloud Deployment
AWS Architecture
Internet
    │
    │ HTTPS / UDP 51820
    ▼
┌─────────────────────────────────────────────────────┐
│                AWS Region (eu-west-1)                │
│  ┌──────────────────────────────────────────────┐   │
│  │              VPC  10.0.0.0/16                │   │
│  │                                              │   │
│  │  ┌─────────────────┐  ┌──────────────────┐  │   │
│  │  │  Public subnet  │  │  Private subnet  │  │   │
│  │  │  10.0.1.0/24    │  │  10.0.2.0/24     │  │   │
│  │  │                 │  │                  │  │   │
│  │  │  EC2 + WireGuard│  │  ECS Fargate     │  │   │
│  │  │  (VPN gateway)  │─▶│  prime_api       │  │   │
│  │  │  sg-vpn         │  │  sg-api          │  │   │
│  │  └─────────────────┘  │        │         │  │   │
│  │                       │        ▼         │  │   │
│  │                       │  RDS PostgreSQL  │  │   │
│  │                       │  prime_db        │  │   │
│  │                       │  sg-db           │  │   │
│  │                       └──────────────────┘  │   │
│  │                                              │   │
│  │  IAM: prime-developers group                 │   │
│  │  IAM: prime-readonly group                   │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
AWS ServicePurposeVPCPrivate network isolating all resourcesEC2 (t3.micro)WireGuard VPN gateway in public subnetECS FargateRuns prime_api container — no server managementRDS PostgreSQLManaged database with automated backupsECRPrivate Docker image registryIAMUser access control and permissionsSecrets ManagerStores DB credentials securely
Prerequisites
Install and configure the AWS CLI:
bash# Install AWS CLI v2
# https://aws.amazon.com/cli/

aws configure
# AWS Access Key ID:     YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region:        eu-west-1
# Default output format: json
Also required: Docker Desktop running locally.
Step 1 — VPC & Subnets
bash# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=prime-vpc}]'
VPC_ID=vpc-xxxxxxxxx   # save from output

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID \
  --enable-dns-hostnames '{"Value":true}'

# Public subnet (VPN gateway)
aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 --availability-zone eu-west-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prime-public}]'

# Private subnet A (API + DB)
aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 --availability-zone eu-west-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prime-private-a}]'

# Private subnet B (RDS requires 2 AZs)
aws ec2 create-subnet --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 --availability-zone eu-west-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prime-private-b}]'

# Internet gateway
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Route table for public subnet
aws ec2 create-route-table --vpc-id $VPC_ID
aws ec2 create-route --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $RTB_ID
Step 2 — Security Groups
bash# VPN gateway — only UDP 51820 inbound
aws ec2 create-security-group --group-name sg-vpn \
  --vpc-id $VPC_ID --description 'WireGuard VPN gateway'
aws ec2 authorize-security-group-ingress --group-id $SG_VPN \
  --protocol udp --port 51820 --cidr 0.0.0.0/0

# API — port 8000 from VPN only
aws ec2 create-security-group --group-name sg-api \
  --vpc-id $VPC_ID --description 'Prime API'
aws ec2 authorize-security-group-ingress --group-id $SG_API \
  --protocol tcp --port 8000 --source-group $SG_VPN

# DB — port 5432 from API only
aws ec2 create-security-group --group-name sg-db \
  --vpc-id $VPC_ID --description 'Prime DB'
aws ec2 authorize-security-group-ingress --group-id $SG_DB \
  --protocol tcp --port 5432 --source-group $SG_API
Step 3 — RDS Database
bash# Subnet group (requires 2 AZs)
aws rds create-db-subnet-group \
  --db-subnet-group-name prime-db-subnet-group \
  --db-subnet-group-description 'Prime DB subnet group' \
  --subnet-ids $PRIVATE_SUBNET_A $PRIVATE_SUBNET_B

# Store credentials securely
aws secretsmanager create-secret \
  --name prime/db-credentials \
  --secret-string '{"username":"prime_user","password":"StrongPass123!"}'

# Launch RDS instance
aws rds create-db-instance \
  --db-instance-identifier prime-db \
  --db-instance-class db.t3.micro \
  --engine postgres --engine-version 16 \
  --master-username prime_user \
  --master-user-password StrongPass123! \
  --db-name prime_db \
  --db-subnet-group-name prime-db-subnet-group \
  --vpc-security-group-ids $SG_DB \
  --no-publicly-accessible \
  --allocated-storage 20

# Wait for it to be ready (~5-10 min)
aws rds wait db-instance-available --db-instance-identifier prime-db

# Get the DB endpoint
aws rds describe-db-instances --db-instance-identifier prime-db \
  --query 'DBInstances[0].Endpoint.Address' --output text
Step 4 — ECR & ECS Fargate
Push image to ECR
bash# Create registry
aws ecr create-repository --repository-name prime-api

# Login and push
aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin \
  YOUR_ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com

docker build -t prime-api .
docker tag prime-api:latest \
  YOUR_ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/prime-api:latest
docker push \
  YOUR_ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/prime-api:latest
Create ECS cluster
bashaws ecs create-cluster --cluster-name prime-cluster \
  --capacity-providers FARGATE
Register task definition
Save as task-definition.json:
json{
  "family": "prime-api-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [{
    "name": "prime-api",
    "image": "ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com/prime-api:latest",
    "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
    "environment": [{
      "name": "DATABASE_URL",
      "value": "postgresql://prime_user:StrongPass123!@RDS_ENDPOINT:5432/prime_db"
    }],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/prime-api",
        "awslogs-region": "eu-west-1",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }]
}
bashaws ecs register-task-definition --cli-input-json file://task-definition.json

aws ecs create-service \
  --cluster prime-cluster \
  --service-name prime-api-service \
  --task-definition prime-api-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$PRIVATE_SUBNET_A],
    securityGroups=[$SG_API],
    assignPublicIp=DISABLED}"
Step 5 — VPN Gateway on EC2
Launch instance
bashaws ec2 run-instances \
  --image-id ami-0905a3c97561e0b69 \
  --instance-type t3.micro \
  --subnet-id $PUBLIC_SUBNET_ID \
  --security-group-ids $SG_VPN \
  --associate-public-ip-address \
  --key-name your-key-pair \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=prime-vpn}]'
Configure WireGuard on EC2
bashssh -i your-key.pem ec2-user@YOUR_EC2_PUBLIC_IP

# Install WireGuard
sudo dnf install wireguard-tools -y

# Generate keys
wg genkey | sudo tee /etc/wireguard/server_private.key
sudo cat /etc/wireguard/server_private.key | wg pubkey | \
  sudo tee /etc/wireguard/server_public.key

# Create config
sudo tee /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(sudo cat /etc/wireguard/server_private.key)
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; \
           iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
EOF

# Enable IP forwarding and start
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
Generate client config for each user
bash# Run on EC2 for each new user
wg genkey | tee client_private.key | wg pubkey > client_public.key

sudo wg set wg0 peer $(cat client_public.key) allowed-ips 10.8.0.2/32

cat << EOF > client.conf
[Interface]
PrivateKey = $(cat client_private.key)
Address = 10.8.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $(sudo cat /etc/wireguard/server_public.key)
Endpoint = YOUR_EC2_PUBLIC_IP:51820
AllowedIPs = 10.0.2.0/24
PersistentKeepalive = 25
EOF
Send client.conf securely to the user. They import it into their WireGuard app and activate.
Step 6 — IAM Users & Permissions
Two groups control access:
GroupCan Doprime-developersDeploy containers, view logs, describe RDS/VPC resourcesprime-readonlyView ECS metrics and CloudWatch logs only
Create groups and policies
bash# Create groups
aws iam create-group --group-name prime-developers
aws iam create-group --group-name prime-readonly
Save as developer-policy.json:
json{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ecr:*", "ecs:*", "rds:Describe*",
      "ec2:Describe*", "logs:*",
      "secretsmanager:GetSecretValue"
    ],
    "Resource": "*",
    "Condition": {
      "StringEquals": { "aws:RequestedRegion": "eu-west-1" }
    }
  }]
}
Save as readonly-policy.json:
json{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ecs:Describe*", "ecs:List*",
      "logs:GetLogEvents", "logs:DescribeLogStreams",
      "cloudwatch:GetMetricStatistics"
    ],
    "Resource": "*"
  }]
}
bash# Attach policies to groups
aws iam create-policy --policy-name prime-developer-policy \
  --policy-document file://developer-policy.json
aws iam attach-group-policy --group-name prime-developers \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/prime-developer-policy

aws iam create-policy --policy-name prime-readonly-policy \
  --policy-document file://readonly-policy.json
aws iam attach-group-policy --group-name prime-readonly \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/prime-readonly-policy

# Add users
aws iam create-user --user-name alice
aws iam add-user-to-group --user-name alice --group-name prime-developers

aws iam create-user --user-name bob
aws iam add-user-to-group --user-name bob --group-name prime-readonly

# Generate access keys
aws iam create-access-key --user-name alice
Step 7 — Verify & Test
bash# Check ECS service is running
aws ecs describe-services --cluster prime-cluster \
  --services prime-api-service \
  --query 'services[0].runningCount'

# Get ECS task private IP
TASK_ARN=$(aws ecs list-tasks --cluster prime-cluster \
  --service-name prime-api-service --query 'taskArns[0]' --output text)

aws ecs describe-tasks --cluster prime-cluster --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value'

# With VPN connected — test API
curl http://ECS_PRIVATE_IP:8000/health
# {"status":"ok"}

curl "http://ECS_PRIVATE_IP:8000/primes?start=1&end=50"

# Without VPN — should time out
curl --max-time 3 http://ECS_PRIVATE_IP:8000/health
Cost Estimate
ResourceMonthly CostECS Fargate (0.5 vCPU, 1GB)~$15RDS db.t3.micro PostgreSQL~$15EC2 t3.micro VPN gateway~$8 (free tier eligible)ECR storage~$0.10/GBData transfer~$1–5Total~$39–43/month
Teardown
Remove all resources in this order to avoid charges:
bashaws ecs delete-service --cluster prime-cluster \
  --service prime-api-service --force
aws ecs delete-cluster --cluster prime-cluster
aws rds delete-db-instance --db-instance-identifier prime-db \
  --skip-final-snapshot
aws ec2 terminate-instances --instance-ids YOUR_EC2_INSTANCE_ID
aws ecr delete-repository --repository-name prime-api --force
aws ec2 delete-security-group --group-id $SG_VPN
aws ec2 delete-security-group --group-id $SG_API
aws ec2 delete-security-group --group-id $SG_DB
# Delete subnets, detach/delete IGW, delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

Terraform Deployment
Instead of running AWS CLI commands manually, you can use Terraform to create and destroy all infrastructure in a single command.
Terraform Project Structure
terraform-prime/
├── main.tf                    ← wires all modules together
├── variables.tf               ← all configurable inputs
├── outputs.tf                 ← useful values printed after apply
├── terraform.tfvars.example   ← copy to terraform.tfvars and fill in
├── deploy.sh                  ← helper: build image + terraform apply
├── .gitignore
└── modules/
    ├── vpc/       ← VPC, subnets, IGW, route tables, DB subnet group
    ├── security/  ← security groups (sg-vpn, sg-api, sg-db)
    ├── rds/       ← RDS PostgreSQL instance
    ├── ecs/       ← ECR repo, ECS cluster, task definition, service
    ├── vpn/       ← EC2 instance + Elastic IP + WireGuard bootstrap
    └── iam/       ← groups, policies, users
Terraform Prerequisites

Terraform >= 1.6 — install on Windows:

powershell   winget install Hashicorp.Terraform
   terraform -version

AWS CLI configured — aws configure
Docker Desktop running
An EC2 key pair — create in AWS Console → EC2 → Key Pairs

Terraform Quick Start
Step 1 — Set up your config file
powershellcopy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
Fill in your values:
hclaws_region    = "eu-west-1"
project       = "prime"
environment   = "dev"
db_password   = "ChangeMe123!"
key_pair_name = "my-key-pair"
ecr_image_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/prime-api:latest"

developer_users = ["alice"]
readonly_users  = ["bob"]
Step 2 — Push your Docker image to ECR first
powershell# Get your AWS account ID
$ACCOUNT_ID = aws sts get-caller-identity --query Account --output text

# Create ECR repository
aws ecr create-repository --repository-name prime-api --region eu-west-1

# Login, build and push
$ECR_URL = "$ACCOUNT_ID.dkr.ecr.eu-west-1.amazonaws.com"

aws ecr get-login-password --region eu-west-1 | `
  docker login --username AWS --password-stdin $ECR_URL

docker build -t prime-api .
docker tag prime-api:latest "$ECR_URL/prime-api:latest"
docker push "$ECR_URL/prime-api:latest"
Update ecr_image_url in terraform.tfvars with the full URL shown above.
Step 3 — Initialise Terraform
powershellterraform init
Step 4 — Preview what will be created
powershellterraform plan
Review the list of resources before applying.
Step 5 — Deploy everything
powershellterraform apply
Type yes when prompted. Takes about 8–12 minutes (RDS takes the longest).
Step 6 — Check outputs
powershellterraform output
You will see:
vpn_public_ip      = "1.2.3.4"
ecr_repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/prime-api"
ssh_command        = "ssh -i my-key-pair.pem ec2-user@1.2.3.4"
developer_group    = "prime-developers"
readonly_group     = "prime-readonly"
Step 7 — Configure WireGuard client
SSH into the VPN instance and generate a peer config for your user:
bashssh -i my-key-pair.pem ec2-user@VPN_PUBLIC_IP

# Generate client keys
wg genkey | tee client_private.key | wg pubkey > client_public.key

# Add client as a peer on the server
sudo wg set wg0 peer $(cat client_public.key) allowed-ips 10.8.0.2/32

# Create client config
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
Copy the client.conf output and import it into your WireGuard app, then activate.
Step 8 — Test the API
With VPN connected, get the ECS task private IP:
powershell$TASK = aws ecs list-tasks --cluster prime-cluster `
  --service-name prime-api-service --query 'taskArns[0]' --output text

aws ecs describe-tasks --cluster prime-cluster --tasks $TASK `
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value'
Then test:
powershellcurl.exe http://ECS_PRIVATE_IP:8000/health
# {"status":"ok"}

curl.exe "http://ECS_PRIVATE_IP:8000/primes?start=1&end=100"
Terraform Modules
ModuleWhat it createsvpcVPC, public subnet, 2 private subnets, internet gateway, route tables, DB subnet groupsecuritysg-vpn (UDP 51820), sg-api (TCP 8000 from VPN only), sg-db (TCP 5432 from API only)rdsRDS PostgreSQL 16 on db.t3.micro, 20GB, 7-day backups, no public accessecsECR repo, ECS cluster, Fargate task definition (0.5 vCPU / 1GB), ECS service, CloudWatch log group, IAM execution rolevpnEC2 t3.micro with WireGuard auto-installed via user_data, Elastic IP for stable endpointiamprime-developers group (deploy access), prime-readonly group (logs/metrics only), one IAM user per name in your tfvars lists
Updating the API
After making code changes, rebuild and push the image, then force a new ECS deployment:
powershell# Push updated image
docker build -t prime-api .
docker tag prime-api:latest "$ECR_URL/prime-api:latest"
docker push "$ECR_URL/prime-api:latest"

# Redeploy ECS service with new image
aws ecs update-service --cluster prime-cluster `
  --service prime-api-service --force-new-deployment
Terraform Teardown
powershellterraform destroy
Type yes to confirm. This removes every resource Terraform created and stops all AWS charges.

Note: If terraform destroy gets stuck on the VPC, destroy ECS first then retry:
powershellterraform destroy -target=module.ecs
terraform destroy


Troubleshooting
ProblemFixdocker compose not foundMake sure Docker Desktop is runningprime_vpn container failsDocker needs WSL2 mode enabled in Docker Desktop settingsAddress already in use on docker composeRun docker network prune -f then retryWireGuard tunnel shows inactiveCheck Endpoint IP in peer.conf — use 127.0.0.1:51820 for localcurl behaves oddly in PowerShellUse curl.exe instead of curlECS task not startingCheck CloudWatch logs: aws logs tail /ecs/prime-apiRDS connection refusedConfirm sg-api is the source group on sg-db, not a CIDRterraform init failsCheck internet connection and that AWS CLI is configured (aws sts get-caller-identity)Error: ECR repository already existsRepo already exists — just push your image and continue with terraform applyRDS times out during terraform applyNormal — RDS takes 8–10 min. Let it run, do not cancel.ECS service stuck at 0/1 runningCheck logs: aws logs tail /ecs/prime-api --followterraform destroy stuck on VPCRun terraform destroy -target=module.ecs first, then terraform destroy
