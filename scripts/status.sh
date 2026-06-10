#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_ENV="$ROOT/scripts/deploy.env"
HOST="127.0.0.1"

if [[ -f "$DEPLOY_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
fi
HOST="${WEREWOLF_HOST:-$HOST}"

check_health() {
  local name=$1 url=$2
  if curl -sf "$url" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    echo "[ok] $name"
  else
    echo "[bad] $name"
  fi
}

check_http() {
  local name=$1 url=$2
  if curl -sf "$url" >/dev/null; then
    echo "[ok] $name"
  else
    echo "[down] $name"
  fi
}

check_health game-backend "http://${HOST}:8000/health" || echo "[down] game-backend"
check_health agent "http://${HOST}:9001/health" || echo "[down] agent"
check_health experiment-backend "http://${HOST}:8100/health" || echo "[down] experiment-backend"
check_http game-frontend "http://${HOST}:5173/" || true
check_http experiment-frontend "http://${HOST}:5174/" || true
