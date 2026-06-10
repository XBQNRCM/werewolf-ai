$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$envFile = Join-Path $root ".env"
$example = Join-Path $root "docker\.env.example"

if (-not (Test-Path $envFile)) {
    Copy-Item $example $envFile
    Write-Host "Created .env from docker/.env.example — edit LLM API keys before running AI games."
}

Set-Location $root
docker compose --env-file .env up -d --build
docker compose --env-file .env ps

Write-Host ""
$gamePort = if ($env:GAME_FRONTEND_PORT) { $env:GAME_FRONTEND_PORT } else { "8080" }
$expPort = if ($env:EXPERIMENT_FRONTEND_PORT) { $env:EXPERIMENT_FRONTEND_PORT } else { "5174" }
Write-Host "Game UI:        http://127.0.0.1:$gamePort"
Write-Host "Experiment UI:  http://127.0.0.1:$expPort"
Write-Host "Smoke spec:     docker/experiment-smoke.json"
