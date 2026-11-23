$ErrorActionPreference = 'Stop'
$infraRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $infraRoot

$images = @(
    @{ Name = 'eureka-server'; Context = (Join-Path $infraRoot 'eureka-server') },
    @{ Name = 'bff'; Context = (Join-Path $workspaceRoot 'ms-barriodigital-bff') },
    @{ Name = 'requests'; Context = (Join-Path $workspaceRoot 'ms-barriodigital-requests') },
    @{ Name = 'catalog'; Context = (Join-Path $workspaceRoot 'ms-barriodigital-catalog') },
    @{ Name = 'crews'; Context = (Join-Path $workspaceRoot 'ms-barriodigital-crews') },
    @{ Name = 'report'; Context = (Join-Path $workspaceRoot 'ms-barriodigital-report') }
)

foreach ($image in $images) {
    Write-Host "Construyendo barriodigital/$($image.Name):local"
    & docker build --tag "barriodigital/$($image.Name):local" $image.Context
    if ($LASTEXITCODE -ne 0) {
        throw "Falló la construcción de barriodigital/$($image.Name):local."
    }
}
