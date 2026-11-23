& (Join-Path $PSScriptRoot 'deploy-stack.ps1') -SkipBuild
if ($LASTEXITCODE -ne 0) {
    throw 'Falló la actualización del stack. Construye las imágenes primero si cambiaron.'
}
