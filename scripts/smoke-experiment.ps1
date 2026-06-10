$ErrorActionPreference = "Stop"

$spec = @{
    name = "smoke-one-game"
    description = "Automated smoke: one 6-player AI game"
    game_backend_base_url = "http://127.0.0.1:8000"
    global_seed = "seed-smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    room_count = 1
    games_per_room = 1
    max_parallel_rooms = 1
    room = @{
        player_count = 6
        rules = @{}
    }
    agents = @(
        @{
            user_name_template = "agent_{experiment_id}_{room_index}_{slot}"
            agent_endpoint = "http://127.0.0.1:9001"
            profile_id = "baseline_v1"
            user_info = @{ type = "ai" }
        }
    )
} | ConvertTo-Json -Depth 6

Write-Host "Creating experiment..."
$created = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8100/experiments" `
    -ContentType "application/json; charset=utf-8" -Body $spec
$expId = $created.experiment_id
Write-Host "Created: $expId"

Write-Host "Starting experiment..."
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8100/experiments/$expId/start" | Out-Null

Write-Host ""
Write-Host "Experiment started. Open:"
Write-Host "  http://127.0.0.1:5174/experiments/$expId"
Write-Host ""
Write-Host "Wait for agents to join and the game to start, then click 观战."
