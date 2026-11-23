param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$infraRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot
$envFile = Join-Path $workspaceRoot '.env'
$stackFile = Join-Path $infraRoot 'docker-stack.yml'

function New-SwarmSecretFromValue([string]$name, [string]$value) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'docker'
    $startInfo.Arguments = "secret create $name -"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "No fue posible iniciar Docker para crear el secreto $name."
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "No fue posible crear el secreto Swarm $name`: $errorOutput"
        }
    } finally {
        $process.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe $envFile. Copia barriodigital-infra\.env.example y configura DB_PASSWORD."
}

foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
        $key = $matches[1]
        $value = $matches[2].Trim()
        if ($value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

if ([string]::IsNullOrWhiteSpace($env:DB_PASSWORD)) {
    throw 'DB_PASSWORD no está definido en el archivo .env del workspace.'
}
if ([string]::IsNullOrWhiteSpace($env:DB_APP_PASSWORD)) {
    throw 'DB_APP_PASSWORD no está definido en el archivo .env del workspace.'
}

$state = & docker info --format '{{.Swarm.LocalNodeState}}'
if ($LASTEXITCODE -ne 0 -or $state -ne 'active') {
    throw 'Inicializa Docker Swarm antes de desplegar: .\scripts\init-swarm.ps1'
}

& docker secret inspect barriodigital_db_password *> $null
if ($LASTEXITCODE -ne 0) {
    New-SwarmSecretFromValue 'barriodigital_db_password' $env:DB_PASSWORD
} else {
    Write-Host 'Se conserva el secreto Swarm root existente; verifica que coincida con la base persistida.'
}

& docker secret inspect barriodigital_db_app_password *> $null
if ($LASTEXITCODE -ne 0) {
    New-SwarmSecretFromValue 'barriodigital_db_app_password' $env:DB_APP_PASSWORD
} else {
    Write-Host 'Se conserva el secreto Swarm de aplicación existente.'
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build-images.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Falló la construcción de imágenes.'
    }
}

Push-Location $infraRoot
try {
    & docker stack deploy --compose-file $stackFile barriodigital
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Swarm no pudo desplegar el stack barriodigital.'
    }
} finally {
    Pop-Location
}
