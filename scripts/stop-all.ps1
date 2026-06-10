$ErrorActionPreference = "SilentlyContinue"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pidFile = Join-Path $root "logs\service-pids.json"

if (Test-Path $pidFile) {
    $services = Get-Content $pidFile -Raw | ConvertFrom-Json
    foreach ($svc in $services) {
        Stop-Process -Id $svc.pid -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped $($svc.name) (pid $($svc.pid))"
    }
    Remove-Item $pidFile -Force
}

# Fallback: kill listeners on known ports
$ports = @(8000, 8100, 9001, 5173, 5174)
foreach ($port in $ports) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $conns) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "Freed port $port (pid $($conn.OwningProcess))"
    }
}

Write-Host "Done."
