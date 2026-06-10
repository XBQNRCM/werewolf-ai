#!/usr/bin/env bash
# macOS / Linux 一键启动
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/logs"
PID_FILE="$LOG_DIR/service-pids"
DEPLOY_ENV="$ROOT/scripts/deploy.env"

mkdir -p "$LOG_DIR"
: >"$PID_FILE"

if [[ -f "$DEPLOY_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
fi

HOST="${WEREWOLF_HOST:-127.0.0.1}"
GAME_BACKEND_PORT="${GAME_BACKEND_PORT:-8000}"
AGENT_PORT="${AGENT_PORT:-9001}"
EXPERIMENT_BACKEND_PORT="${EXPERIMENT_BACKEND_PORT:-8100}"
GAME_FRONTEND_PORT="${GAME_FRONTEND_PORT:-5173}"
EXPERIMENT_FRONTEND_PORT="${EXPERIMENT_FRONTEND_PORT:-5174}"

resolve_python() {
  if [[ -n "${WEREWOLF_PYTHON:-}" ]]; then
    echo "$WEREWOLF_PYTHON"
    return
  fi
  local candidates=(
    "$HOME/miniconda3/envs/werewolf/bin/python"
    "$HOME/anaconda3/envs/werewolf/bin/python"
    "/opt/homebrew/Caskroom/miniconda/base/envs/werewolf/bin/python"
    "/usr/local/Caskroom/miniconda/base/envs/werewolf/bin/python"
  )
  if [[ -n "${CONDA_EXE:-}" ]]; then
    local base
    base="$(dirname "$(dirname "$CONDA_EXE")")"
    candidates=("$base/envs/werewolf/bin/python" "${candidates[@]}")
  fi
  for py in "${candidates[@]}"; do
    if [[ -x "$py" ]]; then
      echo "$py"
      return
    fi
  done
  if command -v conda >/dev/null 2>&1; then
    echo "conda run -n werewolf --no-capture-output python"
    return
  fi
  echo "python3"
}

PYTHON_CMD="$(resolve_python)"
read -r -a PYTHON_RUN <<<"$PYTHON_CMD"
if [[ "$PYTHON_CMD" == "python3" ]]; then
  echo "warn: werewolf env not found, falling back to python3" >&2
fi

start_service() {
  local name=$1 dir=$2
  shift 2
  local log="$LOG_DIR/${name}.log"
  local err="$LOG_DIR/${name}.err.log"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) starting $name" >"$log"
  (
    cd "$dir"
    exec "$@" >>"$log" 2>>"$err"
  ) &
  local pid=$!
  echo "$name $pid" >>"$PID_FILE"
  echo "started $name (pid $pid)"
}

wait_health() {
  local name=$1 url=$2 timeout=${3:-120}
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo "[ok] $name"
      return 0
    fi
    sleep 2
  done
  echo "timeout waiting for $name at $url (see $LOG_DIR)" >&2
  return 1
}

wait_http() {
  local name=$1 url=$2 timeout=${3:-120}
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if curl -sf "$url" | grep -q .; then
      echo "[ok] $name"
      return 0
    fi
    sleep 2
  done
  echo "timeout waiting for $name at $url (see $LOG_DIR)" >&2
  return 1
}

echo "Starting AI Werewolf stack from $ROOT"

start_service game-backend "$ROOT/werewolf-game-system/backend" \
  "${PYTHON_RUN[@]}" -m uvicorn app.main:app --host "$HOST" --port "$GAME_BACKEND_PORT"
start_service agent "$ROOT/werewolf-agent" \
  "${PYTHON_RUN[@]}" -m uvicorn app.main:app --host "$HOST" --port "$AGENT_PORT"
start_service experiment-backend "$ROOT/werewolf-experiments/backend" \
  "${PYTHON_RUN[@]}" -m uvicorn app.main:app --host "$HOST" --port "$EXPERIMENT_BACKEND_PORT"
start_service game-frontend "$ROOT/werewolf-game-system/frontend" npm run dev
start_service experiment-frontend "$ROOT/werewolf-experiments/frontend" npm run dev

echo "Waiting for backends..."
wait_health game-backend "http://${HOST}:${GAME_BACKEND_PORT}/health"
wait_health agent "http://${HOST}:${AGENT_PORT}/health"
wait_health experiment-backend "http://${HOST}:${EXPERIMENT_BACKEND_PORT}/health"

echo "Waiting for frontends..."
wait_http game-frontend "http://${HOST}:${GAME_FRONTEND_PORT}/"
wait_http experiment-frontend "http://${HOST}:${EXPERIMENT_FRONTEND_PORT}/"

echo ""
echo "All services started."
echo "  Game UI:        http://${HOST}:${GAME_FRONTEND_PORT}"
echo "  Experiment UI:  http://${HOST}:${EXPERIMENT_FRONTEND_PORT}"
echo "  PIDs:           $PID_FILE"
echo "  Logs:           $LOG_DIR"
