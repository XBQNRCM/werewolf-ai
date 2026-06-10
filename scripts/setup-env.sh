#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

copy_if_missing() {
  local src=$1 dst=$2
  if [[ ! -f "$src" ]]; then
    echo "skip missing template: $src" >&2
    return
  fi
  if [[ -f "$dst" ]]; then
    echo "keep existing: $dst"
  else
    cp "$src" "$dst"
    echo "created: $dst"
  fi
}

copy_if_missing "$ROOT/werewolf-game-system/.env.example" "$ROOT/werewolf-game-system/.env"
copy_if_missing "$ROOT/werewolf-agent/.env.example" "$ROOT/werewolf-agent/.env"
copy_if_missing "$ROOT/werewolf-experiments/.env.example" "$ROOT/werewolf-experiments/.env"

echo "Done. Edit the three .env files before starting (see docs/configuration.md)."
