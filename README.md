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
- [Task 3 — AWS Cloud Deployment](#task-3--aws-cloud-deployment)
  - [AWS Architecture](#aws-architecture)
  - [Prerequisites](#prerequisites)
  - [Step 1 — VPC & Subnets](#step-1--vpc--subnets)
  - [Step 2 — Security Groups](#step-2--security-groups)
  - [Step 3 — RDS Database](#step-3--rds-database)
  - [Step 4 — ECR & ECS Fargate](#step-4--ecr--ecs-fargate)
  - [Step 5 — VPN Gateway on EC2](#step-5--vpn-gateway-on-ec2)
  - [Step 6 — IAM Users & Permissions](#step-6--iam-users--permissions)
  - [Step 7 — Verify & Test](#step-7--verify--test)
  - [Cost Estimate](#cost-estimate)
  - [Teardown](#teardown)

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