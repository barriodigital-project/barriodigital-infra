param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('bff', 'requests', 'catalog', 'crews', 'report')]
    [string]$Service,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 20)]
    [int]$Replicas
)

$ErrorActionPreference = 'Stop'
& docker service scale "barriodigital_${Service}=$Replicas"
if ($LASTEXITCODE -ne 0) {
    throw "No fue posible escalar el servicio $Service."
}
