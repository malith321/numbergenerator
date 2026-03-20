#!/usr/bin/env bash
# =============================================================================
# setup-vpn.sh — Task 2 deployment helper
#
# What this script does:
#   1. Starts all three containers (db, api, wireguard) via Docker Compose
#   2. Waits for WireGuard to generate the peer (client) config
#   3. Prints the QR code so you can scan it with the WireGuard mobile app
#   4. Prints the .conf file path for desktop WireGuard clients
#   5. Verifies the API is NOT reachable without VPN
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }

echo ""
echo "============================================================"
echo "  Prime Service — Task 2 VPN Setup"
echo "============================================================"
echo ""

# ── Step 1: Build and start all containers ────────────────────────────────────
info "Starting containers (db + api + wireguard)..."
docker compose up -d --build

# ── Step 2: Wait for WireGuard to generate peer configs ──────────────────────
info "Waiting for WireGuard to initialise and generate peer configs..."
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if docker exec prime_vpn test -f /config/peer1/peer1.conf 2>/dev/null; then
        success "WireGuard peer config is ready."
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    error "Timed out waiting for WireGuard peer config."
    error "Check logs: docker logs prime_vpn"
    exit 1
fi

# ── Step 3: Show the QR code (for mobile WireGuard app) ──────────────────────
echo ""
echo "============================================================"
echo "  Scan this QR code with the WireGuard mobile app:"
echo "============================================================"
docker exec prime_vpn cat /config/peer1/peer1.png 2>/dev/null || \
    docker exec prime_vpn /app/show-peer peer1 2>/dev/null || \
    docker exec -it prime_vpn bash -c "qrencode -t ansiutf8 < /config/peer1/peer1.conf" 2>/dev/null || \
    warn "QR display not available — use the .conf file below instead."

# ── Step 4: Show desktop config file ─────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Desktop WireGuard client config (peer1.conf):"
echo "============================================================"
docker exec prime_vpn cat /config/peer1/peer1.conf
echo ""
echo "  File is also saved at:  ./wireguard/config/peer1/peer1.conf"
echo "============================================================"
echo ""

# ── Step 5: Verify API is NOT reachable without VPN ──────────────────────────
info "Verifying API is not directly accessible from host (without VPN)..."
if curl -s --max-time 3 http://localhost:8000/health > /dev/null 2>&1; then
    warn "API is reachable on localhost:8000 without VPN."
    warn "This is expected on some Linux hosts where Docker routes bridge networks"
    warn "back to the host. Add iptables rules (see README) to fully restrict access."
else
    success "API is NOT reachable on localhost:8000 — VPN required."
fi

echo ""
echo "============================================================"
echo "  NEXT STEPS TO CONNECT:"
echo "============================================================"
echo ""
echo "  On macOS / Windows:"
echo "    1. Install WireGuard: https://www.wireguard.com/install/"
echo "    2. Click 'Add Tunnel' → 'Import from file'"
echo "    3. Import: ./wireguard/config/peer1/peer1.conf"
echo "    4. Click 'Activate'"
echo ""
echo "  On Linux:"
echo "    sudo apt install wireguard"
echo "    sudo cp ./wireguard/config/peer1/peer1.conf /etc/wireguard/wg0.conf"
echo "    sudo wg-quick up wg0"
echo ""
echo "  On iPhone / Android:"
echo "    Install 'WireGuard' app → scan the QR code above"
echo ""
echo "  Then access the API at (inside VPN only):"
echo "    http://172.21.0.3:8000/health"
echo "    http://172.21.0.3:8000/primes?start=1&end=100"
echo "    http://172.21.0.3:8000/docs"
echo ""
echo "  CLI (once VPN is connected):"
echo "    python cli.py --base-url http://172.21.0.3:8000 primes 1 100"
echo ""
echo "============================================================"
echo ""
