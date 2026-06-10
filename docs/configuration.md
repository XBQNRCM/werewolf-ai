# 配置说明

本项目支持两类配置方式：

- Docker 全栈：根目录 `.env` 供 `docker compose` 使用。
- 开发模式：三个子模块各自维护 `.env`，互不合并。

不要提交 `.env`、API Key、数据库密码或 provider token。

## 1. Docker 全栈配置

复制模板：

```bash
cp docker/.env.example .env
```

关键变量：

| 变量 | 说明 |
| --- | --- |
| `POSTGRES_USER`、`POSTGRES_PASSWORD`、`POSTGRES_DB` | compose 内置 PostgreSQL 配置 |
| `GAME_FRONTEND_PORT` | 游戏前端对外端口，默认 `8080` |
| `EXPERIMENT_FRONTEND_PORT` | 实验控制台对外端口，默认 `5174` |
| `GAME_ALLOWED_ORIGINS` | 游戏后端 CORS 白名单 |
| `EXPERIMENT_ALLOWED_ORIGINS` | 实验后端 CORS 白名单 |
| `AGENT_NAME` | Agent 服务名 |
| `POLL_INTERVAL_MS` | Agent 轮询间隔 |
| `ARK_API_KEY`、`DEEPSEEK_API_KEY`、`AUTODL_API_KEY` | profile 使用的 LLM API Key |

Docker compose 会自动注入：

- `game-backend` 使用 `werewolf_app` schema。
- `experiment-backend` 使用 `werewolf_experiments` schema。
- `agent` 使用 `werewolf_agent` database。
- `experiment-backend` 通过 `INTERNAL_GAME_BACKEND_URL=http://game-backend:8000` 访问游戏系统。
- 实验前端通过 `/api`、`/game-api`、`/ws` 等 nginx 代理访问后端。

## 2. 开发模式配置

根目录 `.env.example` 只是索引说明。开发模式实际配置在子模块内：

| 模块 | 配置文件 | 模板 | 说明 |
| --- | --- | --- | --- |
| `werewolf-game-system` | `werewolf-game-system/.env` | `werewolf-game-system/.env.example` | 游戏后端数据库、CORS、前端默认 API 地址 |
| `werewolf-agent` | `werewolf-agent/.env` | `werewolf-agent/.env.example` | Agent 数据库、profile 使用的 LLM API Key |
| `werewolf-experiments` | `werewolf-experiments/.env` | `werewolf-experiments/.env.example` | 实验数据库、Agent 数据库引用、内部游戏后端地址、CORS |

一键复制模板：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-env.ps1
```

```bash
bash scripts/setup-env.sh
```

脚本只复制缺失的 `.env`，不会覆盖已存在配置。

## 3. 游戏系统

示例：

```env
DATABASE_URL=postgresql+asyncpg://user:pass@127.0.0.1:5432/werewolf_game
DATABASE_SCHEMA=werewolf_app
APP_ENV=development
ALLOWED_ORIGINS=http://127.0.0.1:5173,http://localhost:5173,http://127.0.0.1:5174,http://localhost:5174
```

不配置 `DATABASE_URL` 时，游戏系统可使用内存模式快速试用；需要持久化 replay、事件和快照时使用 PostgreSQL。

## 4. Agent 服务

示例：

```env
AGENT_NAME=local
DATABASE_URL=postgresql+psycopg://user:pass@127.0.0.1:5432/werewolf_agent
POLL_INTERVAL_MS=800
ARK_API_KEY=
DEEPSEEK_API_KEY=
AUTODL_API_KEY=
```

profile 文件会引用具体的 `api_key_env`。只运行某一类 profile 时，只需要配置该 profile 用到的 Key。

自进化实验建议使用持久数据库，以保留：

- `agent_sessions`
- `deduction_runs` / `deduction_players`
- `action_decisions`
- `strategy_memories`
- `postgame_reviews`
- `llm_calls`

## 5. 实验平台

示例：

```env
EXPERIMENT_DATABASE_URL=postgresql+asyncpg://user:pass@127.0.0.1:5432/werewolf_game
EXPERIMENT_DATABASE_SCHEMA=werewolf_experiments
AGENT_DATABASE_URL=postgresql+psycopg://user:pass@127.0.0.1:5432/werewolf_agent
AGENT_READY_TIMEOUT_SECONDS=300
ALLOWED_ORIGINS=http://127.0.0.1:5174,http://localhost:5174
```

快速试用可以使用内存模式：

```env
EXPERIMENT_DATABASE_URL=memory
```

部署时如果浏览器访问游戏系统的地址和服务端内网地址不同，可以设置：

```env
INTERNAL_GAME_BACKEND_URL=http://game-backend:8000
```

此变量只影响 experiment runner 和下发给 Agent session 的服务端访问地址；实验 JSON 中的 `game_backend_base_url` 仍应填写浏览器可访问的地址。

## 6. 数据库布局

推荐布局：

```text
PostgreSQL
├── database werewolf_game
│   ├── schema werewolf_app
│   └── schema werewolf_experiments
└── database werewolf_agent
```

这样游戏事实、实验调度和 Agent 私有状态保持边界清晰，同时仍便于实验分析脚本跨库读取。
