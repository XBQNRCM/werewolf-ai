$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pidFile = Join-Path $root "logs\service-pids.json"
$logDir = Join-Path $root "logs"
$deployEnv = Join-Path $root "scripts\deploy.env"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (Test-Path $deployEnv) {
    Get-Content $deployEnv | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$' -and $_ -notmatch '^\s*#') {
            $name = $matches[1]
            $value = $matches[2].Trim().Trim('"').Trim("'")
            if ($value) { Set-Item -Path "env:$name" -Value $value }
        }
    }
}

$hostAddr = if ($env:WEREWOLF_HOST) { $env:WEREWOLF_HOST } else { "127.0.0.1" }
$gameBackendPort = if ($env:GAME_BACKEND_PORT) { $env:GAME_BACKEND_PORT } else { "8000" }
$agentPort = if ($env:AGENT_PORT) { $env:AGENT_PORT } else { "9001" }
$experimentBackendPort = if ($env:EXPERIMENT_BACKEND_PORT) { $env:EXPERIMENT_BACKEND_PORT } else { "8100" }
$gameFrontendPort = if ($env:GAME_FRONTEND_PORT) { $env:GAME_FRONTEND_PORT } else { "5173" }
$experimentFrontendPort = if ($env:EXPERIMENT_FRONTEND_PORT) { $env:EXPERIMENT_FRONTEND_PORT } else { "5174" }

function Resolve-PythonCommand {
    if ($env:WEREWOLF_PYTHON) {
        return $env:WEREWOLF_PYTHON
    }
    $candidates = @(
        "C:\Anaconda\envs\werewolf\python.exe",
        "$env:USERPROFILE\anaconda3\envs\werewolf\python.exe",
        "$env:USERPROFILE\miniconda3\envs\werewolf\python.exe",
        "$env:LOCALAPPDATA\miniconda3\envs\werewolf\python.exe"
    )
    if ($env:CONDA_EXE) {
        $condaBase = Split-Path (Split-Path $env:CONDA_EXE -Parent) -Parent
        $candidates = @((Join-Path $condaBase "envs\werewolf\python.exe")) + $candidates
    }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) {
            return "`"$path`""
        }
    }
    return "conda run -n werewolf --no-capture-output python"
}

function Start-BackgroundService {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string]$CommandLine,
        [string]$LogFile
    )
    $stdout = Join-Path $logDir $LogFile
    $stderr = Join-Path $logDir ($LogFile -replace '\.log$', '.err.log')
    "$(Get-Date -Format o) starting $Name" | Set-Content -Encoding UTF8 $stdout

    $inner = "cd /d `"$WorkingDirectory`" && $CommandLine"
    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList @("/c", $inner) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru

    return @{
        name = $Name
        pid = $proc.Id
        cwd = $WorkingDirectory
        log = $stdout
        err = $stderr
    }
}

function Wait-Health {
    param([string]$Name, [string]$Url, [int]$TimeoutSec = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-RestMethod -Uri $Url -TimeoutSec 3
            if ($resp.status -eq "ok") {
                Write-Host "[ok] $Name"
                return
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "Timeout waiting for $Name at $Url (see $logDir)"
}

function Wait-Http {
    param([string]$Name, [string]$Url, [int]$TimeoutSec = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing
            if ($resp.StatusCode -eq 200 -and $resp.Content.Length -gt 100) {
                Write-Host "[ok] $Name"
                return
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "Timeout waiting for $Name at $Url (see $logDir)"
}

Write-Host "Starting AI Werewolf stack from $root"

$python = Resolve-PythonCommand
$uvicorn = "$python -m uvicorn app.main:app --host $hostAddr"

$services = @()
$services += Start-BackgroundService "game-backend" (Join-Path $root "werewolf-game-system\backend") "$uvicorn --port $gameBackendPort" "game-backend.log"
$services += Start-BackgroundService "agent" (Join-Path $root "werewolf-agent") "$uvicorn --port $agentPort" "agent.log"
$services += Start-BackgroundService "experiment-backend" (Join-Path $root "werewolf-experiments\backend") "$uvicorn --port $experimentBackendPort" "experiment-backend.log"
# host/port 已在 vite.config.ts 配置；勿对 npm run dev 传 --host/--port
$services += Start-BackgroundService "game-frontend" (Join-Path $root "werewolf-game-system\frontend") "npm run dev" "game-frontend.log"
$services += Start-BackgroundService "experiment-frontend" (Join-Path $root "werewolf-experiments\frontend") "npm run dev" "experiment-frontend.log"

$services | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $pidFile

Write-Host "Waiting for backends..."
Wait-Health "game-backend" "http://${hostAddr}:${gameBackendPort}/health"
Wait-Health "agent" "http://${hostAddr}:${agentPort}/health"
Wait-Health "experiment-backend" "http://${hostAddr}:${experimentBackendPort}/health"

Write-Host "Waiting for frontends..."
Wait-Http "game-frontend" "http://${hostAddr}:${gameFrontendPort}/"
Wait-Http "experiment-frontend" "http://${hostAddr}:${experimentFrontendPort}/"

Write-Host ""
Write-Host "All services started."
Write-Host "  Game UI:        http://${hostAddr}:${gameFrontendPort}"
Write-Host "  Experiment UI:  http://${hostAddr}:${experimentFrontendPort}"
Write-Host "  PIDs:           $pidFile"
Write-Host "  Logs:           $logDir"
