# 快速开始

## 1. Docker 全栈

Docker 是最少手工步骤的启动方式。

```bash
cp docker/.env.example .env
# 编辑 .env，填入需要的 LLM API Key
docker compose --env-file .env up -d --build
```

访问：

| 入口 | 地址 |
| --- | --- |
| 游戏前端 | http://127.0.0.1:8080 |
| 实验控制台 | http://127.0.0.1:5174 |

实验模板见 [docker/experiment-smoke.json](../docker/experiment-smoke.json)。部署细节见 [deployment.md](./deployment.md)。

## 2. 开发模式

### 2.1 环境要求

- Python 3.11+
- Node.js 20+
- npm
- 可选 PostgreSQL
- 真实 Agent 对局需要 LLM API Key

macOS/Linux 需要 `curl`；停止脚本建议安装 `lsof`。

### 2.2 初始化配置

Windows：

```powershell
cd C:\project\werewolf-ai
powershell -ExecutionPolicy Bypass -File scripts\setup-env.ps1
```

macOS / Linux：

```bash
cd /path/to/werewolf-ai
bash scripts/setup-env.sh
```

脚本会从各子模块 `.env.example` 复制 `.env`，不会覆盖已有文件。随后根据需要填写数据库连接和 LLM API Key。配置说明见 [configuration.md](./configuration.md)。

### 2.3 启动全部服务

| 平台 | 启动 | 停止 | 状态 |
| --- | --- | --- | --- |
| Windows | `scripts\start-all.ps1` | `scripts\stop-all.ps1` | `scripts\status.ps1` |
| macOS / Linux | `bash scripts/start-all.sh` | `bash scripts/stop-all.sh` | `bash scripts/status.sh` |

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-all.ps1
```

macOS / Linux：

```bash
chmod +x scripts/*.sh
bash scripts/start-all.sh
```

脚本会等待后端 `/health` 和前端首页就绪后退出。日志位于根目录 [logs](../logs/)。

### 2.4 访问入口

| 入口 | 地址 | 用途 |
| --- | --- | --- |
| 游戏前端 | http://127.0.0.1:5173 | 手动建房、调试模式、观战/回放 |
| 实验控制台 | http://127.0.0.1:5174 | 批量 AI 对局、实验调度、观战/回放 |

健康检查：

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:9001/health
curl http://127.0.0.1:8100/health
```

## 3. 创建对局

### 3.1 通过实验控制台运行 AI 对局

1. 打开 http://127.0.0.1:5174。
2. 在 JSON 编辑器中创建实验。
3. 点击 `启动`。
4. 在房间矩阵或对局列表中进入观战或回放。

配置示例和字段说明见 [werewolf-experiments/docs/实验控制台使用说明.md](../werewolf-experiments/docs/实验控制台使用说明.md)。

### 3.2 通过游戏前端手动调试

1. 打开 http://127.0.0.1:5173。
2. 输入昵称进入大厅。
3. 创建房间。
4. 手动邀请玩家或使用 AI 补位。
5. 全员 ready 后开始游戏。
6. 使用玩家视角、公共视角或上帝视角观战和回放。

游戏系统设计见 [werewolf-game-system/docs/游戏系统设计文档.md](../werewolf-game-system/docs/游戏系统设计文档.md)。

## 4. 停止服务

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\stop-all.ps1
```

macOS / Linux：

```bash
bash scripts/stop-all.sh
```

## 5. 常见问题

### 前端无法访问后端

检查对应后端健康状态：

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8100/health
```

如果后端正常但浏览器报 CORS 或 Failed to fetch，检查各模块 `.env` 中的 `ALLOWED_ORIGINS`。

### 游戏前端 404

不要对 `npm run dev` 追加 `--host` 或 `--port`。端口已经写在各前端的 `vite.config.ts` 中；额外参数在部分环境下会被误解析为目录。

### 脚本超时

查看 [logs](../logs/) 下对应服务日志。常见原因：

- Python 环境不存在或依赖未安装。
- Node 依赖未安装。
- `.env` 数据库连接不可用。
- 端口被占用。

可以先执行停止脚本，再重新启动。
