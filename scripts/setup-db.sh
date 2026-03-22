#!/usr/bin/env bash
# =============================================================================
# 360 SaaS - Database Setup & Migration Script
# Called by deploy.sh - can also be run standalone:
#   bash scripts/setup-db.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[DB]${NC}    $*"; }
ok()    { echo -e "${GREEN}[DB]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[DB]${NC}    $*"; }
error() { echo -e "${RED}[DB]${NC}    $*" >&2; exit 1; }

# Load .env
ENV_FILE="${ROOT_DIR}/backend/.env"
[[ -f "$ENV_FILE" ]] || error "backend/.env not found. Run scripts/setup-env.sh first."
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:?DB_USER not set}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD not set}"
DB_NAME="${DB_NAME:?DB_NAME not set}"
MIGRATION_FILE="${ROOT_DIR}/backend/src/migrations.sql"

MYSQL_CMD="mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASSWORD}" --silent"

# ---------------------------------------------------------------------------
# 1. Test connection
# ---------------------------------------------------------------------------
log "Testing MySQL connection to ${DB_HOST}:${DB_PORT}..."
if ! ${MYSQL_CMD} -e "SELECT 1;" >/dev/null 2>&1; then
  error "Cannot connect to MySQL at ${DB_HOST}:${DB_PORT}. Check credentials in backend/.env"
fi
ok "MySQL connection successful."

# ---------------------------------------------------------------------------
# 2. Create database if it does not exist
# ---------------------------------------------------------------------------
log "Ensuring database '${DB_NAME}' exists..."
${MYSQL_CMD} -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
ok "Database '${DB_NAME}' ready."

# ---------------------------------------------------------------------------
# 3. Run migrations (idempotent - uses IF NOT EXISTS)
# ---------------------------------------------------------------------------
[[ -f "$MIGRATION_FILE" ]] || error "Migration file not found: $MIGRATION_FILE"

log "Running migrations from ${MIGRATION_FILE}..."
mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" < "$MIGRATION_FILE"
ok "Migrations applied successfully."

# ---------------------------------------------------------------------------
# 4. Verify tables exist
# ---------------------------------------------------------------------------
log "Verifying schema..."
REQUIRED_TABLES=("tenants" "users" "review_cycles" "competencies" "rater_assignments" "survey_responses")
MISSING=0

for TABLE in "${REQUIRED_TABLES[@]}"; do
  COUNT=$(${MYSQL_CMD} "${DB_NAME}" -e \
    "SELECT COUNT(*) FROM information_schema.tables \
     WHERE table_schema='${DB_NAME}' AND table_name='${TABLE}';" 2>/dev/null)
  if [[ "$COUNT" -eq 0 ]]; then
    warn "Missing table: $TABLE"
    MISSING=$((MISSING + 1))
  else
    ok "  Table exists: $TABLE"
  fi
done

[[ "$MISSING" -eq 0 ]] || error "$MISSING table(s) missing after migration. Check migration SQL."
ok "All ${#REQUIRED_TABLES[@]} tables verified."

# ---------------------------------------------------------------------------
# 5. Create application DB user with limited privileges (if root creds provided)
# ---------------------------------------------------------------------------
if [[ "${DB_USER}" == "root" ]] && [[ -n "${DB_APP_USER:-}" ]] && [[ -n "${DB_APP_PASSWORD:-}" ]]; then
  log "Creating application DB user '${DB_APP_USER}'..."
  ${MYSQL_CMD} -e \
    "CREATE USER IF NOT EXISTS '${DB_APP_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_APP_PASSWORD}';"
  ${MYSQL_CMD} -e \
    "GRANT SELECT, INSERT, UPDATE, DELETE ON \`${DB_NAME}\`.* TO '${DB_APP_USER}'@'${DB_HOST}';"
  ${MYSQL_CMD} -e "FLUSH PRIVILEGES;"
  ok "App user '${DB_APP_USER}' created and granted permissions."
fi
