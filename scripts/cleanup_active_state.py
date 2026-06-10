#!/usr/bin/env python3
"""End all waiting/in_game rooms and running agent sessions."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Avoid routing local backend calls through a system HTTP proxy.
os.environ.setdefault("NO_PROXY", "127.0.0.1,localhost")
os.environ.setdefault("no_proxy", "127.0.0.1,localhost")

ROOT = Path(__file__).resolve().parents[1]


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def http_json(method: str, url: str, timeout: float = 30.0) -> tuple[int, object]:
    request = urllib.request.Request(url, method=method, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        try:
            payload = json.loads(body) if body else {"detail": error.reason}
        except json.JSONDecodeError:
            payload = {"detail": body or error.reason}
        return error.code, payload


def cleanup_game_backend(base_url: str) -> dict[str, int]:
    stats = {"voided": 0, "void_failed": 0, "dissolved": 0, "dissolve_failed": 0, "skipped": 0}
    status_code, payload = http_json("GET", f"{base_url}/rooms?status=active")
    if status_code != 200:
        raise RuntimeError(f"list rooms failed: {status_code} {payload}")

    rooms = payload.get("rooms", [])
    print(f"[game] active rooms: {len(rooms)}")

    for room in rooms:
        room_id = room["room_id"]
        status = room.get("status")
        game_ids = room.get("game_ids") or []

        if status == "in_game" and game_ids:
            game_id = game_ids[-1]
            code, result = http_json("POST", f"{base_url}/rooms/{room_id}/games/{game_id}/void")
            if code == 200:
                stats["voided"] += 1
                status = "waiting"
                print(f"[game] voided {room_id} / {game_id}")
            else:
                stats["void_failed"] += 1
                print(f"[game] void failed {room_id} / {game_id}: {result}")
                code2, room_payload = http_json("GET", f"{base_url}/rooms/{room_id}")
                if code2 == 200:
                    status = room_payload.get("status")
                else:
                    stats["skipped"] += 1
                    continue

        if status == "waiting":
            code, result = http_json("POST", f"{base_url}/rooms/{room_id}/dissolve")
            if code == 200:
                stats["dissolved"] += 1
                print(f"[game] dissolved {room_id}")
            else:
                stats["dissolve_failed"] += 1
                print(f"[game] dissolve failed {room_id}: {result}")
        elif status == "in_game":
            stats["skipped"] += 1

    return stats


def cleanup_agent_sessions(agent_base_url: str, database_url: str) -> dict[str, int]:
    stats = {"stopped_via_api": 0, "stop_failed": 0, "marked_stopped_in_db": 0}
    try:
        from sqlalchemy import create_engine, text
    except ImportError:
        print("[agent] sqlalchemy not installed, skip DB lookup")
        return stats

    engine = create_engine(database_url)
    with engine.begin() as conn:
        rows = conn.execute(
            text(
                "SELECT agent_session_id FROM agent_sessions WHERE status = 'running' ORDER BY created_at"
            )
        ).fetchall()
        session_ids = [row[0] for row in rows]

    print(f"[agent] running sessions in DB: {len(session_ids)}")
    remaining: list[str] = []
    for session_id in session_ids:
        code, result = http_json("POST", f"{agent_base_url}/sessions/{session_id}/stop")
        if code == 200:
            stats["stopped_via_api"] += 1
            print(f"[agent] stopped {session_id}")
        else:
            stats["stop_failed"] += 1
            remaining.append(session_id)
            print(f"[agent] stop failed {session_id}: {result}")

    if remaining:
        with engine.begin() as conn:
            result = conn.execute(
                text(
                    "UPDATE agent_sessions "
                    "SET status = 'stopped', stopped_at = NOW() "
                    "WHERE status = 'running'"
                )
            )
            stats["marked_stopped_in_db"] = result.rowcount or 0
        print(f"[agent] marked {stats['marked_stopped_in_db']} sessions stopped in DB")

    return stats


def main() -> int:
    game_env = load_env(ROOT / "werewolf-game-system" / ".env")
    agent_env = load_env(ROOT / "werewolf-agent" / ".env")

    game_base = os.environ.get("GAME_BACKEND_URL", "http://127.0.0.1:8000")
    agent_base = os.environ.get("AGENT_BACKEND_URL", "http://127.0.0.1:9001")
    agent_db = agent_env.get("DATABASE_URL", "")

    print(f"[game] backend: {game_base}")
    status_code, status_payload = http_json("GET", f"{game_base}/status")
    if status_code != 200:
        print(f"[game] status check failed: {status_code} {status_payload}", file=sys.stderr)
        return 1
    print(f"[game] before: {status_payload}")

    game_stats = cleanup_game_backend(game_base)

    status_code, status_payload = http_json("GET", f"{game_base}/status")
    print(f"[game] after: {status_payload}")
    print(f"[game] stats: {game_stats}")

    if agent_db:
        print(f"[agent] backend: {agent_base}")
        agent_stats = cleanup_agent_sessions(agent_base, agent_db)
        print(f"[agent] stats: {agent_stats}")
    else:
        print("[agent] DATABASE_URL missing, skipped")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
