# 部署方式

## 1. 总览

| 方式 | 命令 | 覆盖范围 |
| --- | --- | --- |
| Docker 全栈 | `docker compose --env-file .env up -d --build` | PostgreSQL、游戏系统、Agent、实验平台 |
| 开发脚本 | `scripts/start-all.*` | 使用本机 Python/Node 启动全部服务 |
| 仅游戏系统 Docker | `cd werewolf-game-system && docker compose up -d --build` | 游戏后端和游戏前端，适合只体验规则引擎 |

开源使用推荐 Docker 全栈；需要调试代码时使用开发脚本。

## 2. Docker 全栈

### 2.1 准备

- Docker 24+
- Docker Compose v2
- 至少一个 profile 使用的 LLM API Key

### 2.2 配置

```bash
cp docker/.env.example .env
```

编辑 `.env`，填入需要的模型 Key：

```env
ARK_API_KEY=
DEEPSEEK_API_KEY=
AUTODL_API_KEY=
```

### 2.3 启动

```bash
docker compose --env-file .env up -d --build
```

Windows 也可使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\docker-up.ps1
```

### 2.4 访问

| 入口 | 地址 |
| --- | --- |
| 游戏前端 | http://127.0.0.1:8080 |
| 实验控制台 | http://127.0.0.1:5174 |

游戏前端面向单房间体验和人工交互，可以创建房间、真人行动、AI 补位、观战和回放；实验控制台面向批量 Agent 对局，可以创建多房间实验、调度 Agent session、查看 runner events、summary 和 LLM trace。二者都通过游戏后端读取权威对局事实。

### 2.5 创建 smoke 实验

实验模板：

```text
docker/experiment-smoke.json
```

Docker 网络约定：

- `game_backend_base_url` 使用浏览器可访问地址，例如 `http://127.0.0.1:5174/game-api`。
- `agent_endpoint` 使用容器内地址 `http://agent:9001`。
- `experiment-backend` 通过 `INTERNAL_GAME_BACKEND_URL=http://game-backend:8000` 访问游戏后端。
- Agent session payload 也会使用内网 game backend 地址。

### 2.6 停止

```bash
docker compose --env-file .env down
```

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\docker-down.ps1
```

保留数据库 volume 时，下一次启动会复用历史数据。需要彻底清理时再手动删除 Docker volume。

## 3. 开发模式

开发模式使用本机 Python/Node 进程，端口如下：

| 服务 | 端口 |
| --- | --- |
| 游戏系统后端 | `8000` |
| 游戏系统前端 | `5173` |
| Agent Player Server | `9001` |
| 实验控制台后端 | `8100` |
| 实验控制台前端 | `5174` |

初始化配置：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-env.ps1
```

启动：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
```

macOS / Linux：

```bash
bash scripts/setup-env.sh
bash scripts/start-all.sh
```

停止：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\stop-all.ps1
```

```bash
bash scripts/stop-all.sh
```

详细步骤见 [quickstart.md](./quickstart.md) 和 [configuration.md](./configuration.md)。

## 4. Docker 网络结构

```text
browser
  ├─ :8080  game-frontend
  │          ├─ /api → game-backend
  │          ├─ /ws  → game-backend
  │          └─ /agent → agent
  └─ :5174  experiment-frontend
             ├─ /api → experiment-backend
             ├─ /game-api → game-backend
             └─ /ws → game-backend

experiment-backend → game-backend
experiment-backend → agent
agent → game-backend
postgres → werewolf_game / werewolf_agent
```

## 5. 仅游戏系统 Docker

如果只需要体验游戏规则引擎和游戏前端：

```bash
cd werewolf-game-system
cp docker.env.example .env
docker compose up -d --build
```

该模式不包含 Agent 服务和实验平台。
