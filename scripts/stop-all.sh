#!/usr/bin/env bash
# macOS / Linux 停止全部服务
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT/logs/service-pids"
DEPLOY_ENV="$ROOT/scripts/deploy.env"

if [[ -f "$DEPLOY_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
fi

GAME_BACKEND_PORT="${GAME_BACKEND_PORT:-8000}"
AGENT_PORT="${AGENT_PORT:-9001}"
EXPERIMENT_BACKEND_PORT="${EXPERIMENT_BACKEND_PORT:-8100}"
GAME_FRONTEND_PORT="${GAME_FRONTEND_PORT:-5173}"
EXPERIMENT_FRONTEND_PORT="${EXPERIMENT_FRONTEND_PORT:-5174}"

kill_pid() {
  local pid=$1
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    echo "stopped pid $pid"
  fi
}

kill_port() {
  local port=$1
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids=$(lsof -ti "tcp:${port}" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
      echo "freed port $port"
    fi
  elif command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/tcp" 2>/dev/null || true
    echo "freed port $port"
  fi
}

if [[ -f "$PID_FILE" ]]; then
  while read -r name pid; do
    [[ -z "${name:-}" || -z "${pid:-}" ]] && continue
    kill_pid "$pid"
    echo "stopped $name"
  done <"$PID_FILE"
  rm -f "$PID_FILE"
fi

for port in "$GAME_BACKEND_PORT" "$AGENT_PORT" "$EXPERIMENT_BACKEND_PORT" "$GAME_FRONTEND_PORT" "$EXPERIMENT_FRONTEND_PORT"; do
  kill_port "$port"
done

echo "Done."
