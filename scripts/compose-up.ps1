$ErrorActionPreference = 'Stop'
$infraRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot
$envFile = Join-Path $workspaceRoot '.env'

if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe $envFile. Copia barriodigital-infra\.env.example y configura DB_PASSWORD."
}

& docker compose --env-file $envFile --file (Join-Path $infraRoot 'compose.yaml') up -d --build
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Compose no pudo iniciar la plataforma.'
}
