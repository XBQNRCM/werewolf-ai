"""Export a single day-2 decision walkthrough for the docs/report Agent appendix.

Pipeline shown: visible-state clipping -> belief -> decision -> postgame review.
Game / experiment identifiers are intentionally kept out of the exported payload.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import psycopg2
from psycopg2.extras import RealDictCursor

GAME_ID = "game_9c026e3850"
PLAYER = "carol"
SPEECH_RID = "game_9c026e3850:12:2:day_speech:-:1:0:carol"
OUT_PATH = (
    Path(__file__).resolve().parents[1]
    / "docs/report/assets/walkthrough/context-walkthrough.json"
)


def load_database_urls() -> dict[str, str]:
    root = Path(__file__).resolve().parents[1]
    urls: dict[str, str] = {}
    for sub, key in (("werewolf-game-system", "game"), ("werewolf-agent", "agent")):
        env_path = root / sub / ".env"
        for line in env_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("DATABASE_URL=") and not line.strip().startswith("#"):
                val = line.split("=", 1)[1].strip()
                urls[key] = val.replace("postgresql+asyncpg://", "postgresql://").replace(
                    "postgresql+psycopg://", "postgresql://"
                )
    if "game" not in urls or "agent" not in urls:
        raise RuntimeError("DATABASE_URL not found in .env files")
    return urls


def parse_sections(prompt: str) -> list[dict]:
    if not prompt:
        return []
    sections = []
    for part in re.split(r"(?=【[^】]+】)", prompt):
        part = part.strip()
        if not part:
            continue
        m = re.match(r"【([^】]+)】\s*(.*)", part, re.DOTALL)
        if m:
            sections.append({"title": m.group(1), "content": m.group(2).strip()})
    return sections


def llm_response_text(response_payload: dict | None) -> str:
    if not response_payload:
        return ""
    if isinstance(response_payload.get("content"), str):
        return response_payload["content"]
    raw = response_payload.get("raw_response") or {}
    choices = raw.get("choices") or []
    if choices:
        return (choices[0].get("message") or {}).get("content") or ""
    return ""


def fetch_llm(cur, **where) -> dict | None:
    clauses = " AND ".join(f"{k} = %s" for k in where)
    cur.execute(
        f"""
        SELECT request_payload, response_payload, status
        FROM llm_calls WHERE {clauses}
        ORDER BY created_at LIMIT 1
        """,
        list(where.values()),
    )
    row = cur.fetchone()
    if not row:
        return None
    user_prompt = ""
    for m in (row["request_payload"] or {}).get("messages", []):
        if m.get("role") == "user":
            user_prompt = m.get("content") or ""
    return {
        "status": row["status"],
        "sections": parse_sections(user_prompt),
        "response_text": llm_response_text(row["response_payload"]),
    }


def event_text(payload: dict, event_type: str) -> str:
    if isinstance(payload, dict):
        if payload.get("description"):
            return payload["description"]
        if event_type == "seer_checked":
            return f"预言家查验 {payload.get('target_user_name')} → {payload.get('result')}"
        if event_type == "action_submitted":
            at = payload.get("action_type")
            tgt = payload.get("target_user_name")
            return f"{at}" + (f" → {tgt}" if tgt else "")
        if event_type == "phase_changed":
            return f"进入阶段 {payload.get('phase')}"
    return event_type


def build_clipping(gcur, clipped_events: list[dict]) -> dict:
    clipped_seqs = {e.get("sequence") for e in clipped_events}
    # Player-view events carry readable descriptions; reuse them for visible raw rows.
    clipped_text = {
        e.get("sequence"): (
            e.get("description") or event_text(e.get("payload") or {}, e.get("event_type"))
        )
        for e in clipped_events
    }
    cutoff = max(clipped_seqs)
    gcur.execute(
        """
        SELECT sequence, day, phase, visibility, event_type, payload
        FROM werewolf_app.game_events
        WHERE game_id = %s AND sequence <= %s
        ORDER BY sequence
        """,
        (GAME_ID, cutoff),
    )
    raw = []
    for r in gcur.fetchall():
        payload = r["payload"] if isinstance(r["payload"], dict) else {}
        seq = r["sequence"]
        text = clipped_text.get(seq) or event_text(payload, r["event_type"])
        raw.append(
            {
                "sequence": seq,
                "day": r["day"],
                "phase": r["phase"],
                "visibility": r["visibility"],
                "event_type": r["event_type"],
                "text": text,
                "visible_to_self": seq in clipped_seqs,
            }
        )
    clipped = [
        {
            "sequence": e.get("sequence"),
            "phase": e.get("phase"),
            "text": e.get("description") or event_text(e.get("payload") or {}, e.get("event_type")),
        }
        for e in clipped_events
    ]
    return {
        "cutoff_sequence": cutoff,
        "raw_count": len(raw),
        "visible_count": len(clipped),
        "hidden_count": len(raw) - len(clipped),
        "raw_events": raw,
        "clipped_events": clipped,
    }


def main():
    urls = load_database_urls()
    gconn = psycopg2.connect(urls["game"])
    aconn = psycopg2.connect(urls["agent"])

    with gconn.cursor(cursor_factory=RealDictCursor) as gcur, aconn.cursor(
        cursor_factory=RealDictCursor
    ) as acur:
        gcur.execute("SELECT * FROM werewolf_app.games WHERE game_id = %s", (GAME_ID,))
        game = dict(gcur.fetchone())
        current_index = game["game_index"]

        acur.execute(
            """
            SELECT gp.*, s.agent_identity_id, s.profile_id, s.room_id, s.agent_session_id
            FROM game_participations gp
            JOIN agent_sessions s ON s.agent_session_id = gp.agent_session_id
            WHERE gp.game_id = %s AND gp.user_name = %s
            """,
            (GAME_ID, PLAYER),
        )
        wolf = dict(acur.fetchone())
        sid = wolf["agent_session_id"]
        room_id = wolf["room_id"]
        aid = wolf["agent_identity_id"]

        acur.execute(
            """
            SELECT COUNT(*) cnt FROM strategy_memories
            WHERE room_id = %s AND user_name = %s AND status = 'active'
              AND source_game_id IS NOT NULL AND source_game_id != %s
            """,
            (room_id, aid, GAME_ID),
        )
        prior_mem_cnt = acur.fetchone()["cnt"]

        # ---- the day-2 speech action context (player view) ----
        gcur.execute(
            "SELECT context FROM werewolf_app.action_requests WHERE request_id = %s",
            (SPEECH_RID,),
        )
        ctx = gcur.fetchone()["context"]
        vs = ctx.get("visible_state") or {}
        clipped_events = vs.get("events") or []

        # The raw action request envelope the agent receives when polling a pending action.
        # Game / request identifiers are intentionally omitted.
        request_envelope = {
            "day": ctx.get("day"),
            "phase": ctx.get("phase"),
            "subphase": ctx.get("subphase"),
            "user_name": ctx.get("user_name"),
            "state_version": ctx.get("state_version"),
            "legal_actions": ctx.get("legal_actions"),
            "action_instruction": {
                "text": (ctx.get("action_instruction") or {}).get("text"),
                "response_format": "<JSON Schema · oneOf[speak]，强制结构化输出>",
            },
            "visible_state": "<按 carol 身份裁剪后的玩家视角，详见下方对比>",
        }

        clipping = build_clipping(gcur, clipped_events)
        clipping["self_role"] = vs.get("role")
        clipping["known_wolves"] = vs.get("known_wolves")
        clipping["investigations"] = vs.get("investigations") or []
        clipping["players"] = [
            {
                "user_name": p.get("user_name"),
                "alive": p.get("alive"),
                "revealed_role": p.get("revealed_role"),
            }
            for p in vs.get("players") or []
        ]

        # ---- decision + belief ----
        acur.execute(
            """
            SELECT action_decision_id, action_type, target_user_name, content,
                   selected_memory_ids, selected_static_strategy_ids, deduction_run_id
            FROM action_decisions
            WHERE agent_session_id = %s AND request_id = %s
            """,
            (sid, SPEECH_RID),
        )
        dec = dict(acur.fetchone())

        belief = None
        if dec.get("deduction_run_id"):
            acur.execute(
                """
                SELECT target_user_name, deduced_role, role_confidence, statement_reliability, evidence
                FROM deduction_players WHERE deduction_run_id = %s ORDER BY target_user_name
                """,
                (dec["deduction_run_id"],),
            )
            players = [dict(r) for r in acur.fetchall()]
            belief_llm = fetch_llm(
                acur, deduction_run_id=dec["deduction_run_id"], call_kind="belief"
            )
            belief = {"players": players, "llm": belief_llm}

        # selected memories with normalized score
        memories = []
        if dec.get("selected_memory_ids"):
            acur.execute(
                """
                SELECT memory_id, role, phase, score, content, source_game_id
                FROM strategy_memories WHERE memory_id = ANY(%s)
                """,
                (dec["selected_memory_ids"],),
            )
            rows = [dict(r) for r in acur.fetchall()]
            src_ids = [r["source_game_id"] for r in rows if r["source_game_id"]]
            gcur.execute(
                "SELECT game_id, game_index FROM werewolf_app.games WHERE game_id = ANY(%s)",
                (src_ids,),
            )
            idx_map = {r["game_id"]: r["game_index"] for r in gcur.fetchall()}
            for r in rows:
                src_idx = idx_map.get(r["source_game_id"])
                lifespan = (current_index - src_idx + 1) if src_idx else 1
                lifespan = max(lifespan, 1)
                r["lifespan"] = lifespan
                r["normalized_score"] = round(r["score"] / lifespan, 2)
            rows.sort(key=lambda x: x["normalized_score"], reverse=True)
            memories = rows

        decision = {
            "action_instruction": (ctx.get("action_instruction") or {}).get("text", ""),
            "llm": fetch_llm(
                acur, action_decision_id=dec["action_decision_id"], call_kind="decision"
            ),
            "memories": memories,
            "submitted": {
                "action_type": dec["action_type"],
                "target_user_name": dec["target_user_name"],
                "content": dec["content"],
            },
        }

        # ---- postgame review ----
        acur.execute(
            """
            SELECT postgame_review_id, summary, belief_errors, decision_errors,
                   created_memory_ids, raw_output
            FROM postgame_reviews WHERE agent_session_id = %s AND game_id = %s
            """,
            (sid, GAME_ID),
        )
        pg = acur.fetchone()
        postgame = None
        if pg:
            pg = dict(pg)
            created = []
            if pg["created_memory_ids"]:
                acur.execute(
                    "SELECT memory_id, role, phase, content FROM strategy_memories WHERE memory_id = ANY(%s)",
                    (pg["created_memory_ids"],),
                )
                created = [dict(r) for r in acur.fetchall()]

            # Deterministic score updates applied to recalled memories after the game.
            raw = pg["raw_output"] or {}
            score_updates = raw.get("score_updates") or []
            su_ids = [u["memory_id"] for u in score_updates if u.get("memory_id")]
            su_content = {}
            if su_ids:
                acur.execute(
                    "SELECT memory_id, role, phase, content FROM strategy_memories WHERE memory_id = ANY(%s)",
                    (su_ids,),
                )
                su_content = {r["memory_id"]: dict(r) for r in acur.fetchall()}
            updates = []
            for u in score_updates:
                meta = su_content.get(u.get("memory_id"), {})
                delta = u.get("delta") or 0
                new_score = u.get("new_score")
                updates.append(
                    {
                        "role": meta.get("role"),
                        "phase": meta.get("phase"),
                        "content": meta.get("content"),
                        "delta": delta,
                        "new_score": new_score,
                        "old_score": (new_score - delta) if new_score is not None else None,
                        "reason": u.get("reason"),
                    }
                )

            postgame = {
                "summary": pg["summary"],
                "belief_errors": pg["belief_errors"] or [],
                "decision_errors": pg["decision_errors"] or [],
                "created_memories": created,
                "helpful_count": len(raw.get("helpful_memory_ids") or []),
                "score_updates": updates,
                "winner": game["winner"],
                "self_won": game["winner"] == vs.get("role"),
                "llm": fetch_llm(
                    acur, postgame_review_id=pg["postgame_review_id"], call_kind="postgame_review"
                ),
            }

        payload = {
            "meta": {
                "player": PLAYER,
                "self_role": vs.get("role"),
                "profile_id": wolf["profile_id"],
                "prior_memory_count": prior_mem_cnt,
                "day": 2,
                "winner": game["winner"],
                "alive_now": [p["user_name"] for p in clipping["players"] if p["alive"]],
            },
            "intro": (
                "一局 8 人自进化狼人杀的第 2 天。跟随一个自进化狼人玩家 carol 的「白天发言」决策，"
                "依次查看：游戏后端如何把权威状态裁剪成该玩家的 visible state，"
                "Agent 如何据此做身份推断（belief），如何组装行动决策（decision）prompt，"
                "以及终局后如何复盘（postgame review）并沉淀跨局记忆。"
            ),
            "request": request_envelope,
            "clipping": clipping,
            "belief": belief,
            "decision": decision,
            "postgame": postgame,
        }

    gconn.close()
    aconn.close()

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8"
    )
    print(f"Wrote {OUT_PATH}")
    print(
        f"clipping: {clipping['raw_count']} raw -> {clipping['visible_count']} visible "
        f"({clipping['hidden_count']} hidden)"
    )


if __name__ == "__main__":
    main()
