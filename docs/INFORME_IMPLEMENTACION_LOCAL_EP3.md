# Informe de implementación y verificación local EP3

**Fecha:** 23 de noviembre de 2026
**Workspace:** `Barrio Digital`
**Alcance:** preparación local y revisión de los cambios; no se desplegó AWS ni se hizo push.

## 1. Resultado

Se retiraron RabbitMQ, Kafka, Audit y Notify de la arquitectura activa, preservando los repositorios de Audit/Notify. El conjunto ejecutable queda en BFF, Requests, Catalog, Crews, Report, Eureka y MySQL. Se añadieron Dockerfiles multi-stage, Compose, definición Swarm de un solo nodo, scripts PowerShell, inicialización de bases y documentación de pendientes cloud/CI.

## 2. Cambios entregados

- BFF y OpenAPI ya no exponen Audit; se removieron el cliente, controlador, servicio y DTO correspondientes.
- Se retiraron los contratos OpenAPI/AsyncAPI activos de Audit, RabbitMQ y Kafka. Las demás especificaciones activas se conservaron.
- Requests, Catalog, Crews y Report requieren la credencial de base de datos configurada; Compose usa el usuario limitado `barriodigital_app`, no root.
- Se separaron las contraseñas de MySQL root y del usuario de aplicación. En Compose se leen desde `.env`; en Swarm se montan como secretos. Los valores locales no se imprimen ni se versionan.
- BFF y Requests tienen límites HTTP configurables de conexión/lectura; valores predeterminados `2s`/`5s`.
- Se aislaron las pruebas con H2 donde corresponde y se desactiva Eureka en los contextos de test.
- La documentación explica el flujo actual y deja explícito que Report no tiene una fuente de escritura integrada.

## 3. Verificación

| Comprobación | Resultado |
|---|---|
| Maven `clean verify` secuencial en BFF, Requests, Catalog, Crews y Report | 31 pruebas, 0 fallos/errores |
| Maven Wrapper tras los cambios de timeouts en BFF y Requests | BFF 6/6; Requests 8/8 |
| Construcción Docker de seis componentes | Completada |
| Reconstrucción BFF y Requests después de sus cambios HTTP | Completada |
| Parseo de los scripts PowerShell | Sin errores sintácticos |
| Validación de `compose.yaml` con Docker Compose | Correcta |
| Validación de `docker-stack.yml` con Docker Stack | Correcta |
| Prueba de inicio/salud e integración Requests→Catalog en Compose | Correcta; todos los servicios saludables, registro Eureka y creación HTTP 201 |
| Inicialización y despliegue Swarm | Correctos en un nodo; servicios 1/1 y BFF escalado 2/2, luego restaurado a 1/1 |

Eureka no se compiló con `clean verify` sobre el workspace porque había un `.class` modificado previamente en `eureka-server/target`. Ese archivo no se sobrescribió; sí se construyó la imagen Eureka desde el código fuente.

El primer arranque limpio de MySQL tardó más de 30 segundos y excedió el período de gracia inicial del healthcheck. Se aumentó `start_period` a 180 segundos en Compose y Swarm. Al probar Swarm se detectó que el pipeline nativo de Windows PowerShell añadía CRLF al contenido de los secretos; el byte adicional causaba `Access denied` al usuario de aplicación. `deploy-stack.ps1` ahora transmite bytes UTF-8 exactos por stdin de Docker, sin añadir salto de línea. Se recrearon los secretos de prueba y las aplicaciones conectaron a MySQL.

## 4. Restricciones operativas y alcance de lo no probado

- Los puertos host `8080` y `8086` ya estaban ocupados por contenedores ajenos a BarrioDigital. No se detuvieron ni modificaron. El `.env` local fija BFF en `8090`; Eureka publica `8761`.
- No se ejecutaron scripts `.ps1` porque la política de PowerShell local bloquea su invocación. No se cambió ni se eludió esa política; se usaron comandos Docker equivalentes y el parser para validar sintaxis.
- Las imágenes son locales y no se publicaron en un registry. La verificación de Swarm, si se completa, es de un solo nodo; no demuestra alta disponibilidad ni topología manager/worker.
- La URI JWKS del ejemplo es un placeholder. No se pudo considerar autenticación real del BFF validada hasta configurar una URI y tokens de prueba válidos.
- No se limpiaron imágenes, cachés ni volúmenes del usuario para liberar espacio. No se ejecutó AWS, no se crearon recursos cloud ni workflows de GitHub Actions.
- Compose y el stack Swarm se detuvieron después de las pruebas; el volumen MySQL y el modo Swarm local se conservaron. Los contenedores preexistentes ajenos al proyecto no se tocaron.

## 5. Rúbrica IE1–IE17

La solicitud de implementación menciona IE1–IE17, pero no incluye definiciones ni criterios verificables para esos identificadores. No se asigna aprobado/reprobado ni se inventa el mapeo. Se necesita la rúbrica oficial para completar esa matriz.

## 6. Repositorios y cambios locales

El workspace no tiene un `.git` raíz: cada componente mantiene su propio repositorio. Se crearon commits locales, sin push:

| Repositorio | Commit |
|---|---|
| Contracts | `105c107` |
| BFF | `f51b66f` |
| Requests | `ccff02a` |
| Catalog | `8af1f6c` |
| Crews | `4ce2515` |
| Report | `512ecdc` |
| Infra | `fb42178` |

Requests ya tenía un commit adicional local antes de estos cambios; se preservó. El `.class` modificado previamente de Eureka se dejó fuera del commit. El `.env` está en la raíz del workspace, no se incorporó a ningún repositorio y sus valores no se incluyeron en la documentación.

Audit y Notify siguen limpios. Se intentó mover cada repositorio al directorio hermano `Barrio Digital-archived`, pero Windows informó que otro proceso mantiene abierto cada directorio. No se borró ni copió contenido; el traslado físico queda pendiente de liberar el bloqueo.

## 7. Próximos pasos

1. Completar la prueba de salud y el flujo real Requests→Catalog en Compose.
2. Si el entorno lo permite, probar Swarm local de un nodo, escalar temporalmente un servicio sin estado y volver al número de réplicas inicial.
3. Mover Audit/Notify al directorio de archivo hermano conservando `.git`. Windows rechazó el movimiento porque los directorios están abiertos por otro proceso; los repositorios siguen intactos en el workspace. Reintentar cuando se libere ese bloqueo.
4. Recibir la rúbrica IE1–IE17 para calificar sus criterios sin inferencias.
5. Revisar diffs y crear commits locales pequeños por repositorio, excluyendo `.env`, artefactos `target` preexistentes y logs temporales.
