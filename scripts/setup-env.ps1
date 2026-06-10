$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$pairs = @(
    @{ src = "werewolf-game-system\.env.example"; dst = "werewolf-game-system\.env" },
    @{ src = "werewolf-agent\.env.example"; dst = "werewolf-agent\.env" },
    @{ src = "werewolf-experiments\.env.example"; dst = "werewolf-experiments\.env" }
)

foreach ($p in $pairs) {
    $src = Join-Path $root $p.src
    $dst = Join-Path $root $p.dst
    if (-not (Test-Path $src)) {
        Write-Warning "skip missing template: $($p.src)"
        continue
    }
    if (Test-Path $dst) {
        Write-Host "keep existing: $($p.dst)"
    } else {
        Copy-Item $src $dst
        Write-Host "created: $($p.dst)"
    }
}

Write-Host "Done. Edit the three .env files before starting (see docs/configuration.md)."
