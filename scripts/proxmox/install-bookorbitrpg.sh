#!/usr/bin/env bash
#
# Self-contained installer for the bookorbitrpg fork inside a Debian LXC.
#
# Mirrors the community-scripts BookOrbit installer, but builds from THIS fork's
# git repository (no GitHub Release required) so private/personal forks work.
#
# Run as root inside a fresh Debian 12/13 LXC:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/7thExtinctionrpg/bookorbitrpg/main/scripts/proxmox/install-bookorbitrpg.sh)"
#
# Overridable via env, e.g.:
#   REPO_BRANCH=main PORT=3000 bash install-bookorbitrpg.sh
#   REPO_URL=https://<TOKEN>@github.com/7thExtinctionrpg/bookorbitrpg.git bash install-bookorbitrpg.sh   # private repo
#
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
REPO_URL="${REPO_URL:-https://github.com/7thExtinctionrpg/bookorbitrpg.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
APP_DIR="${APP_DIR:-/opt/bookorbitrpg}"
DATA_DIR="${DATA_DIR:-/opt/bookorbitrpg-data}"
BOOKS_DIR="${BOOKS_DIR:-/opt/bookorbitrpg-books}"
PY_DIR="${PY_DIR:-/opt/bookorbitrpg-python}"
SERVICE="${SERVICE:-bookorbitrpg}"
PORT="${PORT:-3000}"
NODE_MAJOR="${NODE_MAJOR:-24}"
PG_VERSION="${PG_VERSION:-16}"
PG_DB_NAME="${PG_DB_NAME:-bookorbit}"
PG_DB_USER="${PG_DB_USER:-bookorbit}"

LOCAL_IP="$(hostname -I | awk '{print $1}')"
export DEBIAN_FRONTEND=noninteractive

log() { echo -e "\n\033[1;32m▶ $*\033[0m"; }

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

# ── System dependencies ──────────────────────────────────────────────────────
log "Installing base dependencies"
apt-get update -qq
apt-get install -y --no-install-recommends \
  build-essential ffmpeg poppler-utils git curl ca-certificates gnupg jq openssl lsb-release sudo

# ── PostgreSQL ${PG_VERSION} + pgvector (PGDG) ───────────────────────────────
log "Installing PostgreSQL ${PG_VERSION} + pgvector"
install -d /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq
apt-get install -y "postgresql-${PG_VERSION}" "postgresql-${PG_VERSION}-pgvector"
systemctl enable -q --now postgresql

# ── Database, role, extensions ───────────────────────────────────────────────
log "Creating database and role"
PG_DB_PASS="$(openssl rand -hex 24)"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${PG_DB_USER}'" | grep -q 1 \
  || sudo -u postgres psql -qc "CREATE ROLE ${PG_DB_USER} LOGIN PASSWORD '${PG_DB_PASS}';"
# Ensure the password matches this run even if the role already existed.
sudo -u postgres psql -qc "ALTER ROLE ${PG_DB_USER} WITH PASSWORD '${PG_DB_PASS}';"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DB_NAME}'" | grep -q 1 \
  || sudo -u postgres psql -qc "CREATE DATABASE ${PG_DB_NAME} OWNER ${PG_DB_USER};"
for ext in uuid-ossp pg_trgm vector; do
  sudo -u postgres psql -d "${PG_DB_NAME}" -qc "CREATE EXTENSION IF NOT EXISTS \"${ext}\";"
done

# ── Node.js ${NODE_MAJOR} + corepack ─────────────────────────────────────────
log "Installing Node.js ${NODE_MAJOR}"
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
apt-get install -y nodejs
corepack enable

# ── uv (Python runtime for Kobo cloudscraper) ────────────────────────────────
log "Installing uv (Python runtime)"
curl -fsSL https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:${PATH}"

# ── Clone the fork ───────────────────────────────────────────────────────────
log "Cloning ${REPO_URL} (${REPO_BRANCH})"
rm -rf "${APP_DIR}"
git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${APP_DIR}"
cd "${APP_DIR}"

# ── Build client + server ────────────────────────────────────────────────────
log "Building application (this can take several minutes)"
PNPM_VERSION="$(jq -r '.packageManager | ltrimstr("pnpm@")' package.json)"
corepack prepare "pnpm@${PNPM_VERSION}" --activate
pnpm install --frozen-lockfile
pnpm --filter client run build-only
pnpm --filter server run build
cp -r "${APP_DIR}/client/dist" "${APP_DIR}/server/public"
mkdir -p "${APP_DIR}/server/migrations"
cp -r "${APP_DIR}/server/src/db/migrations/." "${APP_DIR}/server/migrations/"
chmod +x "${APP_DIR}/server/bin/kepubify/"* 2>/dev/null || true

# ── Python venv ──────────────────────────────────────────────────────────────
log "Setting up Python runtime"
uv venv "${PY_DIR}"
uv pip install --python "${PY_DIR}/bin/python" -r "${APP_DIR}/server/requirements/kobo-cloudscraper.txt"

# ── Data dirs + .env ─────────────────────────────────────────────────────────
log "Configuring application"
mkdir -p "${DATA_DIR}/covers" "${DATA_DIR}/book-bucket" "${BOOKS_DIR}"
JWT_SECRET="$(openssl rand -hex 32)"
SETUP_BOOTSTRAP_TOKEN="$(openssl rand -hex 16)"
cat > "${APP_DIR}/.env" <<EOF
NODE_ENV=production
PORT=${PORT}
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
JWT_SECRET=${JWT_SECRET}
SETUP_BOOTSTRAP_TOKEN=${SETUP_BOOTSTRAP_TOKEN}
APP_URL=http://${LOCAL_IP}:${PORT}
CLIENT_URL=http://${LOCAL_IP}:${PORT}
NODE_OPTIONS=--max-old-space-size=2048
APP_DATA_PATH=${DATA_DIR}
KOBO_CLOUDSCRAPER_PYTHON=${PY_DIR}/bin/python
BOOK_DOCK_PATH=${DATA_DIR}/book-bucket
EOF
chmod 600 "${APP_DIR}/.env"

# ── systemd service ──────────────────────────────────────────────────────────
log "Creating systemd service: ${SERVICE}"
cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=BookOrbit RPG Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}/server
EnvironmentFile=${APP_DIR}/.env
ExecStartPre=/usr/bin/node ${APP_DIR}/server/dist/scripts/migrate.js
ExecStart=/usr/bin/node ${APP_DIR}/server/dist/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now "${SERVICE}"

cat <<EOF

────────────────────────────────────────────────────────────
 bookorbitrpg installed.

   URL:          http://${LOCAL_IP}:${PORT}
   Setup token:  ${SETUP_BOOTSTRAP_TOKEN}
   App dir:      ${APP_DIR}
   Books dir:    ${BOOKS_DIR}   (mount your library here)
   Service:      systemctl status ${SERVICE}
   Logs:         journalctl -u ${SERVICE} -f

 Saved to /root/bookorbitrpg.creds
────────────────────────────────────────────────────────────
EOF
printf 'URL: http://%s:%s\nSetup token: %s\n' "${LOCAL_IP}" "${PORT}" "${SETUP_BOOTSTRAP_TOKEN}" > /root/bookorbitrpg.creds
chmod 600 /root/bookorbitrpg.creds
