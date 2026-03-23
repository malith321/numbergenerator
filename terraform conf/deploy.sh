#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Build, push Docker image to ECR, then apply Terraform
#
# Usage:
#   ./deploy.sh             # full deploy (terraform apply)
#   ./deploy.sh --push-only # just build and push the Docker image
#   ./deploy.sh --plan-only # just run terraform plan
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }

PUSH_ONLY=false
PLAN_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--push-only" ]] && PUSH_ONLY=true
  [[ "$arg" == "--plan-only" ]] && PLAN_ONLY=true
done

# ── Read config from tfvars ───────────────────────────────────────────────────
AWS_REGION=$(grep aws_region terraform.tfvars | awk -F'"' '{print $2}')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/prime-api"

# ── Step 1: Build and push Docker image ──────────────────────────────────────
info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

info "Building Docker image..."
docker build -t prime-api ../

info "Tagging image..."
docker tag prime-api:latest "$ECR_URL:latest"

info "Pushing to ECR..."
docker push "$ECR_URL:latest"
success "Image pushed to $ECR_URL:latest"

[[ "$PUSH_ONLY" == true ]] && exit 0

# ── Step 2: Terraform deploy ──────────────────────────────────────────────────
info "Initialising Terraform..."
terraform init

info "Running terraform plan..."
terraform plan -var="ecr_image_url=$ECR_URL:latest"

[[ "$PLAN_ONLY" == true ]] && exit 0

info "Applying Terraform..."
terraform apply -var="ecr_image_url=$ECR_URL:latest" -auto-approve

success "Deployment complete!"
echo ""
terraform output
