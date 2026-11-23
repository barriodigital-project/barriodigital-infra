param(
    [string]$AdvertiseAddress
)

$ErrorActionPreference = 'Stop'
$state = & docker info --format '{{.Swarm.LocalNodeState}}'
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible consultar Docker Swarm.'
}

if ($state -eq 'active') {
    Write-Host 'Docker Swarm ya está activo; no se modificó el clúster.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($AdvertiseAddress)) {
    & docker swarm init
} else {
    & docker swarm init --advertise-addr $AdvertiseAddress
}
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible inicializar el manager local de Docker Swarm.'
}
