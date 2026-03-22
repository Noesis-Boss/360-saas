#!/usr/bin/env bash
# =============================================================================
# 360 SaaS - Full Deployment Script
# Usage: bash deploy.sh [--env production|staging|development]
# Requires: git, node 18+, npm, mysql client, pm2 (auto-installed)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colors & helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

DEPLOY_ENV="production"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --env) DEPLOY_ENV="$2"; shift 2 ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

echo -e "\n${BOLD}================================================${NC}"
echo -e "${BOLD}  360 SaaS Deployment  [env: ${DEPLOY_ENV}]${NC}"
echo -e "${BOLD}================================================${NC}\n"

# ---------------------------------------------------------------------------
# Step 1 - Check prerequisites
# ---------------------------------------------------------------------------
log "Checking prerequisites..."

command -v git  >/dev/null 2>&1 || error "git is not installed."
command -v node >/dev/null 2>&1 || error "Node.js is not installed. Install Node 18+ first."
command -v npm  >/dev/null 2>&1 || error "npm is not installed."
command -v mysql >/dev/null 2>&1 || error "MySQL client is not installed. Run: sudo apt install mysql-client"

NODE_VER=$(node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null && echo ok || echo fail)
[[ "$NODE_VER" == "ok" ]] || error "Node.js 18+ required. Found: $(node --version)"

# Install pm2 globally if missing
if ! command -v pm2 >/dev/null 2>&1; then
  log "Installing pm2 globally..."
  npm install -g pm2 || error "Failed to install pm2"
fi

# Install serve globally if missing (for frontend static hosting)
if ! command -v serve >/dev/null 2>&1; then
  log "Installing serve globally..."
  npm install -g serve || error "Failed to install serve"
fi

ok "All prerequisites met."

# ---------------------------------------------------------------------------
# Step 2 - Load / validate environment files
# ---------------------------------------------------------------------------
log "Loading environment configuration..."

BACKEND_ENV="${SCRIPT_DIR}/backend/.env"
FRONTEND_ENV="${SCRIPT_DIR}/frontend/.env"

if [[ ! -f "$BACKEND_ENV" ]]; then
  warn "backend/.env not found. Running environment setup..."
  bash "${SCRIPT_DIR}/scripts/setup-env.sh"
fi

if [[ ! -f "$FRONTEND_ENV" ]]; then
  warn "frontend/.env not found. Running environment setup..."
  bash "${SCRIPT_DIR}/scripts/setup-env.sh" --frontend-only
fi

# Source backend env to validate required vars
set -a
# shellcheck source=/dev/null
source "$BACKEND_ENV"
set +a

for VAR in DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME JWT_SECRET; do
  [[ -n "${!VAR:-}" ]] || error "Missing required env var: $VAR (check backend/.env)"
done

ok "Environment configuration loaded."

# ---------------------------------------------------------------------------
# Step 3 - Pull latest code (if inside a git repo)
# ---------------------------------------------------------------------------
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Pulling latest changes from git..."
  git -C "$SCRIPT_DIR" pull --ff-only || warn "git pull failed - continuing with current code."
  ok "Code is up to date."
else
  warn "Not a git repository - skipping git pull."
fi

# ---------------------------------------------------------------------------
# Step 4 - Database setup & migrations
# ---------------------------------------------------------------------------
log "Running database setup and migrations..."
bash "${SCRIPT_DIR}/scripts/setup-db.sh"
ok "Database ready."

# ---------------------------------------------------------------------------
# Step 5 - Backend dependencies
# ---------------------------------------------------------------------------
log "Installing backend dependencies..."
cd "${SCRIPT_DIR}/backend"
npm ci --omit=dev 2>&1 | tail -3
ok "Backend dependencies installed."

# ---------------------------------------------------------------------------
# Step 6 - Frontend build
# ---------------------------------------------------------------------------
log "Installing frontend dependencies..."
cd "${SCRIPT_DIR}/frontend"
npm ci 2>&1 | tail -3

log "Building frontend..."
npm run build 2>&1 | tail -5
ok "Frontend built successfully."

# ---------------------------------------------------------------------------
# Step 7 - Start / restart services with PM2
# ---------------------------------------------------------------------------
log "Starting services with PM2..."
bash "${SCRIPT_DIR}/scripts/start.sh" "$DEPLOY_ENV"

# ---------------------------------------------------------------------------
# Step 8 - Post-deploy health check
# ---------------------------------------------------------------------------
log "Running health checks..."
sleep 3  # Give services a moment to initialise
bash "${SCRIPT_DIR}/scripts/health-check.sh"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}================================================"
echo -e "  Deployment complete!  [$(date '+%Y-%m-%d %H:%M:%S')]"
echo -e "================================================${NC}\n"

echo -e "  Backend API : http://localhost:${PORT:-3000}"
echo -e "  Frontend    : http://localhost:5000"
echo -e "  PM2 status  : pm2 list"
echo -e "  PM2 logs    : pm2 logs\n"
