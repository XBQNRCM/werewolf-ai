# 贡献指南

## 仓库结构

本仓库为 **AI 狼人杀** 统一入口，包含三个子模块：

- `werewolf-game-system` — 对局引擎
- `werewolf-agent` — Agent Player Server
- `werewolf-experiments` — 实验控制台

## 开发环境

**Docker（推荐验证全栈）**

```bash
cp docker/.env.example .env
docker compose --env-file .env up -d --build
```

**本地开发**

1. Fork 本仓库并 clone（含 submodule：`git clone --recurse-submodules`）
2. 安装 Python 3.11、Node 20
3. 运行 `scripts/setup-env.ps1` 或 `scripts/setup-env.sh`
4. 按 [docs/configuration.md](./docs/configuration.md) 填写 `.env`
5. 按 [docs/quickstart.md](./docs/quickstart.md) 启动服务

## 提交规范

- 不要提交 `.env`、API Key、内网地址、答辩私有材料（`private-docs/`）
- 配置模板只改 `.env.example`
- 改动尽量聚焦单一模块；跨模块协议变更需同步更新 `docs/architecture.md`

## 测试

```bash
cd werewolf-game-system/backend && pytest -q
cd werewolf-agent && pytest -q
cd werewolf-experiments/backend && pytest -q
cd werewolf-experiments/frontend && npm test
```

## Pull Request

1. 说明影响的模块与行为变化
2. 附本地验证步骤（如何启动、如何复现）
3. 若改 API 或实验配置 schema，更新对应 `docs/`
