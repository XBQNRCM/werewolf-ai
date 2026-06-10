$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$deployEnv = Join-Path $root "scripts\deploy.env"
$hostAddr = "127.0.0.1"

if (Test-Path $deployEnv) {
    Get-Content $deployEnv | ForEach-Object {
        if ($_ -match '^\s*WEREWOLF_HOST=(.*)$' -and $_ -notmatch '^\s*#') {
            $v = $matches[1].Trim().Trim('"').Trim("'")
            if ($v) { $hostAddr = $v }
        }
    }
}

$checks = @(
    @{ name = "game-backend"; url = "http://${hostAddr}:8000/health"; type = "health" },
    @{ name = "agent"; url = "http://${hostAddr}:9001/health"; type = "health" },
    @{ name = "experiment-backend"; url = "http://${hostAddr}:8100/health"; type = "health" },
    @{ name = "game-frontend"; url = "http://${hostAddr}:5173/"; type = "http" },
    @{ name = "experiment-frontend"; url = "http://${hostAddr}:5174/"; type = "http" }
)

foreach ($c in $checks) {
    try {
        if ($c.type -eq "health") {
            $r = Invoke-RestMethod $c.url -TimeoutSec 3
            if ($r.status -eq "ok") { Write-Host "[ok] $($c.name)" } else { Write-Host "[bad] $($c.name)" }
        } else {
            $r = Invoke-WebRequest $c.url -TimeoutSec 3 -UseBasicParsing
            if ($r.StatusCode -eq 200) { Write-Host "[ok] $($c.name)" } else { Write-Host "[bad] $($c.name)" }
        }
    } catch {
        Write-Host "[down] $($c.name)"
    }
}
