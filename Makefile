.PHONY: up down logs ps setup-env

up:
	docker compose --env-file .env up -d --build

down:
	docker compose --env-file .env down

logs:
	docker compose --env-file .env logs -f

ps:
	docker compose --env-file .env ps

setup-env:
	cp -n docker/.env.example .env 2>/dev/null || cp docker/.env.example .env
