$ErrorActionPreference = 'Stop'
$infraRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot
$envFile = Join-Path $workspaceRoot '.env'

if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe $envFile."
}

& docker compose --env-file $envFile --file (Join-Path $infraRoot 'compose.yaml') down
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Compose no pudo detener la plataforma.'
}
