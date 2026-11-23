param(
    [ValidateSet('', 'bff', 'requests', 'catalog', 'crews', 'report', 'eureka', 'mysql')]
    [string]$Service = ''
)

$ErrorActionPreference = 'Stop'
& docker node ls
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible listar los nodos Swarm.'
}
& docker stack services barriodigital
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible listar los servicios del stack.'
}
& docker stack ps barriodigital --no-trunc
if ($LASTEXITCODE -ne 0) {
    throw 'No fue posible consultar las tareas del stack.'
}

if (-not [string]::IsNullOrWhiteSpace($Service)) {
    & docker service logs --tail 100 "barriodigital_$Service"
    if ($LASTEXITCODE -ne 0) {
        throw "No fue posible leer los logs de $Service."
    }
}
