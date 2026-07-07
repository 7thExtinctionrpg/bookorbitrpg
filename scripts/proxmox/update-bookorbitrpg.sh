#!/usr/bin/env bash
#
# Update an existing bookorbitrpg LXC install: pull the latest fork commit,
# rebuild, run migrations, and restart. Run as root inside the LXC:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/7thExtinctionrpg/bookorbitrpg/main/scripts/proxmox/update-bookorbitrpg.sh)"
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/bookorbitrpg}"
PY_DIR="${PY_DIR:-/opt/bookorbitrpg-python}"
SERVICE="${SERVICE:-bookorbitrpg}"
REPO_BRANCH="${REPO_BRANCH:-main}"
export PATH="/root/.local/bin:${PATH}"

log() { echo -e "\n\033[1;32m▶ $*\033[0m"; }

if [[ ! -d "${APP_DIR}/.git" ]]; then
  echo "No git checkout at ${APP_DIR}. Run install-bookorbitrpg.sh first." >&2
  exit 1
fi

log "Stopping ${SERVICE}"
systemctl stop "${SERVICE}"

log "Backing up .env"
cp -a "${APP_DIR}/.env" "${APP_DIR}/.env.bak.$(date +%s)"

log "Pulling latest ${REPO_BRANCH}"
cd "${APP_DIR}"
git fetch --depth 1 origin "${REPO_BRANCH}"
git reset --hard "origin/${REPO_BRANCH}"

log "Rebuilding"
PNPM_VERSION="$(jq -r '.packageManager | ltrimstr("pnpm@")' package.json)"
corepack prepare "pnpm@${PNPM_VERSION}" --activate
pnpm install --frozen-lockfile
pnpm --filter client run build-only
pnpm --filter server run build
rm -rf "${APP_DIR}/server/public"
cp -r "${APP_DIR}/client/dist" "${APP_DIR}/server/public"
mkdir -p "${APP_DIR}/server/migrations"
cp -r "${APP_DIR}/server/src/db/migrations/." "${APP_DIR}/server/migrations/"
chmod +x "${APP_DIR}/server/bin/kepubify/"* 2>/dev/null || true

log "Updating Python runtime"
uv pip install --python "${PY_DIR}/bin/python" -r "${APP_DIR}/server/requirements/kobo-cloudscraper.txt"

log "Starting ${SERVICE}"
systemctl start "${SERVICE}"
log "Update complete. Logs: journalctl -u ${SERVICE} -f"
