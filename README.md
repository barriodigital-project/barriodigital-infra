# BarrioDigital — infraestructura local

Este repositorio contiene Eureka y los artefactos para ejecutar localmente los
servicios activos de BarrioDigital. Las instrucciones se orientan a Windows y
PowerShell; no realizan operaciones contra AWS ni configuran GitHub Actions.

## Arquitectura local activa

```text
                         ┌───────────────┐
Browser ── localhost ──► │ BFF :8080     │ ──JWT/REST──┐
                         └───────────────┘             │
                                                       ▼
             ┌─────────────┬─────────────┬────────────┬────────────┐
             │ Requests    │ Catalog     │ Crews      │ Report     │
             │ :8081       │ :8082       │ :8083      │ :8087      │
             └──────┬──────┴──────┬──────┴─────┬──────┴─────┬──────┘
                    └──────────────┴────────────┴────────────┘
                                          │
                                          ▼
                              MySQL :3306 (red interna)

 Eureka :8761 ◄──── los clientes activos se registran y descubren servicios
```

Solo BFF y Eureka publican puertos al host en Compose. Las APIs de dominio y
MySQL permanecen en la red Docker. BFF valida JWT/roles; Requests consulta
Catalog por Eureka. Cada servicio conserva su base lógica en MySQL.

Componentes activos:

| Componente | Puerto | Responsabilidad |
|---|---:|---|
| BFF | 8080 | Fachada REST, seguridad JWT, autorización y llamadas downstream. |
| Requests | 8081 | Solicitudes, propietarios y transiciones de estado. |
| Catalog | 8082 | Tipos de trámite, requisitos y cupos. |
| Crews | 8083 | Cuadrillas y asignaciones. |
| Report | 8087 | Consultas de reportería sobre su base local. |
| Eureka | 8761 | Registro y descubrimiento de servicios. |
| MySQL | 3306 interno | Bases `requests_db`, `catalog_db`, `crews_db` y `report_db`. |

Audit y Notify fueron retirados de la arquitectura ejecutable. Sus repositorios
se conservan sin cambios; el traslado físico fuera del workspace quedó pendiente
porque Windows reportó que otro proceso mantiene abiertos ambos directorios.
RabbitMQ y Kafka no se levantan ni se usan. Report conserva sus endpoints, pero
no tiene un proceso de carga de `RequestReport`; no se deben presentar sus
respuestas vacías como estadísticas productivas. Las notificaciones con
SQS/Lambda son una etapa cloud futura.

## Requisitos

- Docker Desktop con Docker Engine y Docker Compose v2.
- JDK 21 para compilar/probar fuera de Docker.
- PowerShell 5.1 o superior.
- `DB_PASSWORD` local, no vacío. No se debe compartir ni versionar.
- Para peticiones autenticadas al BFF, un URI JWKS válido configurado localmente.

## Variables de entorno

El `.env` del workspace raíz necesita `DB_PASSWORD` para MySQL root y
`DB_APP_PASSWORD` para el usuario limitado de las aplicaciones. El archivo
local existente se conservó; se agregó el secreto de aplicación sin mostrar ni
sustituir el valor root. En este workspace `BFF_PORT` se fijó a `8090` porque
el `8080` del host ya estaba ocupado. Si se prepara un workspace nuevo, crear
`.env` desde este ejemplo y reemplazar ambos valores antes de ejecutar:

```powershell
Copy-Item barriodigital-infra\.env.example .env
```

Variables:

| Variable | Uso | Valor si se omite |
|---|---|---|
| `DB_PASSWORD` | Contraseña local de root de MySQL; no se entrega a los servicios Spring. | Requerida. |
| `DB_APP_PASSWORD` | Contraseña del usuario `barriodigital_app`, limitado a las cuatro bases de aplicación. | Requerida. |
| `BFF_PORT` | Puerto de loopback para BFF. | `8080` |
| `EUREKA_PORT` | Puerto de loopback para Eureka. | `8761` |
| `JWT_JWK_SET_URI` | JWKS para validar JWT en BFF. | `https://example.invalid/...` (placeholder; no permite autenticar). |
| `CORS_ALLOWED_ORIGINS` | Orígenes web autorizados por CORS. | `http://localhost:4200` |
| `HTTP_CONNECT_TIMEOUT` | Tiempo máximo para establecer llamadas HTTP desde BFF y Requests. | `2s` |
| `HTTP_READ_TIMEOUT` | Tiempo máximo para recibir respuestas HTTP desde BFF y Requests. | `5s` |

No usar las contraseñas locales de Compose en ambientes compartidos. El stack
Swarm usa dos secretos Docker creados desde las variables correspondientes;
los procesos Spring reciben solo la credencial de aplicación mediante un
archivo secreto.

## Ejecución con Docker Compose

Desde la raíz del workspace:

```powershell
.\barriodigital-infra\scripts\compose-up.ps1
```

El comando construye seis imágenes Java y levanta Eureka, MySQL, Catalog,
Requests, Crews, Report y BFF. En un arranque limpio, el script SQL crea de
forma idempotente las cuatro bases lógicas y concede acceso al usuario de
aplicación, no a root. El volumen `mysql_data` persiste los datos entre
reinicios.

Verificación de salud:

```powershell
.\barriodigital-infra\scripts\smoke-test.ps1
docker compose --env-file .env -f barriodigital-infra\compose.yaml ps
```

Puntos de entrada expuestos solo en loopback:

- BFF: `http://localhost:${BFF_PORT}/actuator/health` (en el `.env` actual, puerto `8090`; valor de ejemplo, `8080`).
- Eureka: `http://localhost:8761/` y `http://localhost:8761/eureka/apps`

Las APIs de Requests, Catalog, Crews y Report no tienen puertos publicados en
Compose. Para probarlas manualmente se puede usar un cliente temporal en la red
de Compose, sin abrir esos puertos al host. Para autenticar el BFF es necesario
reemplazar el JWKS de ejemplo por uno válido y usar un JWT emitido para ese
proveedor.

Detención sin borrar datos:

```powershell
.\barriodigital-infra\scripts\compose-down.ps1
```

No usar `docker compose down --volumes` si se deben conservar los datos locales.
Para reinicializar las bases hay que respaldar y eliminar conscientemente el
volumen desde Docker Desktop; el procedimiento no forma parte del arranque
normal.

## Compilación y pruebas Maven

Cada servicio tiene su propio Maven Wrapper; no existe un reactor Maven en la
raíz. Ejemplo:

```powershell
Push-Location ms-barriodigital-requests
try {
    .\mvnw.cmd clean verify
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de Requests.' }
} finally {
    Pop-Location
}
```

Repetir en `ms-barriodigital-bff`, `ms-barriodigital-catalog`,
`ms-barriodigital-crews`, `ms-barriodigital-report` y
`barriodigital-infra\eureka-server`. Las pruebas de los módulos de persistencia
usan H2; la prueba de flujo entre servicios debe ejecutarse además con Compose.

## Dockerfiles

Los Dockerfiles de los seis componentes activos son multi-stage: Maven/JDK 21
construye el JAR y una imagen JRE 21 mínima ejecuta como usuario no root. Los
contextos excluyen `.git`, `.env`, `target` y archivos del IDE. Las imágenes
incluyen una health check HTTP; el proceso Java usa `exec` para recibir señales
de parada. Compose construye automáticamente al usar `compose-up.ps1`.

Para construir sin arrancar el entorno:

```powershell
.\barriodigital-infra\scripts\build-images.ps1
```

Las etiquetas locales son `barriodigital/{eureka-server,bff,requests,catalog,crews,report}:local`.
No se publican en un registry.

## Docker Swarm local

### Inicializar y desplegar

En un solo nodo local:

```powershell
.\barriodigital-infra\scripts\init-swarm.ps1
.\barriodigital-infra\scripts\deploy-stack.ps1
.\barriodigital-infra\scripts\inspect-stack.ps1
```

El despliegue construye las imágenes localmente, crea (si no existen) los
secretos `barriodigital_db_password` y `barriodigital_db_app_password` sin
mostrar su contenido y despliega
`barriodigital-infra\docker-stack.yml`. `docker stack deploy` no usa `build`,
`depends_on` ni el archivo `.env`; por eso el script importa variables al
proceso y llama al builder antes del deploy. Los servicios reintentan mediante
restart policies en lugar de depender de un orden de arranque.

Actualización después de construir las imágenes:

```powershell
.\barriodigital-infra\scripts\update-stack.ps1
```

Inspección:

```powershell
.\barriodigital-infra\scripts\inspect-stack.ps1
.\barriodigital-infra\scripts\inspect-stack.ps1 -Service requests
docker service ps barriodigital_requests --no-trunc
docker service logs --tail 100 barriodigital_requests
docker node ls
```

Escalado de servicios stateless:

```powershell
.\barriodigital-infra\scripts\scale-service.ps1 -Service requests -Replicas 2
docker service ls
docker service ps barriodigital_requests
```

Se permiten escalar BFF, Requests, Catalog, Crews o Report de forma explícita.
No se escala MySQL ni Eureka. El volumen de MySQL es local al nodo manager y el
servicio está fijado a ese nodo: esto sirve para demostrar un stack local de un
nodo, pero **no** constituye alta disponibilidad ni persistencia compartida
para un Swarm multinodo. El cupo de Catalog tampoco es una reserva distribuida
atómica, por lo que aumentar réplicas no garantiza exclusión de solicitudes
concurrentes.

### Manager y worker

Para añadir un nodo a un Swarm real, el administrador debe configurar red,
firewall, almacenamiento y direccionamiento antes de unirlo. En un manager:

```powershell
docker swarm join-token worker
docker node ls
```

Ejecutar el comando `docker swarm join` generado únicamente en el host worker
autorizado y tratar el token como secreto. El script
`init-swarm.ps1 -AdvertiseAddress <IP-manager>` permite especificar la IP del
manager al inicializarlo. No se probó un clúster de varios nodos, ni
replicación/failover de MySQL, ni distribución de imágenes a workers. Para
multinodo se requiere un registry accesible y una estrategia de almacenamiento
persistente distribuido o una base de datos administrada.

Un secreto Swarm es inmutable. Para rotarlo se necesita planificar la
actualización de la contraseña de MySQL y los servicios dependientes; el
despliegue no reemplaza secretos existentes automáticamente.

## Endpoints y health checks

Los servicios Spring exponen Actuator `health`, `info` y `metrics` dentro de la
red. El healthcheck de Eureka consulta `/eureka/apps`. No se publican puertos
de administración ni de base al host en Compose. Las rutas de negocio y roles
se detallan en los README de cada servicio y en los contratos OpenAPI.

## Solución de problemas

| Síntoma | Comprobación |
|---|---|
| Falta `DB_PASSWORD` | Revisar que exista el `.env` raíz y que contenga la clave, sin imprimir el valor. |
| MySQL queda `unhealthy` | Revisar `docker compose logs mysql`; comprobar que el volumen no tenga credenciales de un arranque anterior incompatibles. |
| Servicio no aparece en Eureka | Revisar salud de Eureka, `EUREKA_SERVER_URL` y `docker compose logs <servicio>`. |
| Requests no descubre Catalog | Confirmar que Catalog aparezca como `CATALOG-MS` y que `CATALOG_SERVICE_URL` use el ID lógico `http://catalog-ms`. |
| BFF responde 401/403 | Es esperado sin JWT válido o sin rol; configurar un JWKS real y claims de roles antes de probar rutas protegidas. |
| Cambio de contraseña no se aplica en Swarm | La contraseña de MySQL ya persistida y el secreto externo no se rotan automáticamente; planificar la rotación. |
| Docker no puede construir | Verificar Docker Engine, espacio disponible y acceso al registry de imágenes base/Maven Central. |
| Puerto ocupado | Cambiar `BFF_PORT` o `EUREKA_PORT` en `.env`; no exponer servicios internos para resolver conflictos. |

## AWS y CI/CD

Esta fase no despliega recursos cloud ni crea workflows. La planificación
ordenada de ECR, EC2/Swarm, red, base de datos, SQS/Lambda, API Gateway,
Cognito, IAM y GitHub Actions está en
[`docs/PENDIENTES_CLOUD_CICD.md`](./docs/PENDIENTES_CLOUD_CICD.md).

## Estructura

```text
barriodigital-infra/
├── compose.yaml
├── docker-stack.yml
├── docker/mysql/init/01-databases.sql
├── eureka-server/
├── scripts/
└── docs/
```
