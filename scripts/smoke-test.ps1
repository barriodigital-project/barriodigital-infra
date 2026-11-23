param(
    [int]$BffPort = 0,
    [int]$EurekaPort = 8761
)

$ErrorActionPreference = 'Stop'
if ($BffPort -eq 0) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $envFile = Join-Path $workspaceRoot '.env'
    if (Test-Path -LiteralPath $envFile) {
        foreach ($line in Get-Content -LiteralPath $envFile) {
            if ($line -match '^\s*BFF_PORT\s*=\s*(\d+)\s*$') {
                $BffPort = [int]$matches[1]
                break
            }
        }
    }
    if ($BffPort -eq 0) {
        $BffPort = 8080
    }
}

$bff = Invoke-RestMethod -Uri "http://localhost:$BffPort/actuator/health" -TimeoutSec 10
if ($bff.status -ne 'UP') {
    throw "BFF health no está UP: $($bff.status)"
}

$registry = Invoke-WebRequest -Uri "http://localhost:$EurekaPort/eureka/apps" -TimeoutSec 10 -UseBasicParsing
if ($registry.StatusCode -ne 200) {
    throw "Eureka respondió HTTP $($registry.StatusCode)."
}

Write-Host 'BFF y Eureka responden correctamente.'
