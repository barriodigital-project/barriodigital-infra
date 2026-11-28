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
| `JWT_JWK_SET_URI` | JWKS de Cognito para validar la firma JWT del BFF. | URL del User Pool configurado. |
| `JWT_ISSUER_URI` | Issuer esperado en el claim `iss`. | URL del User Pool configurado. |
| `JWT_CLIENT_ID` | App client esperado en los access tokens de Cognito. | Client ID configurado. |
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
de Compose, sin abrir esos puertos al host. Para autenticar el BFF se requiere
un access token válido de Cognito para el issuer y client ID configurados.

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

## Despliegue AWS con Docker Swarm

El stack AWS reutiliza los nombres de servicios, la red overlay, la
configuración de Eureka y el volumen `mysql_data` del stack local. MySQL queda
fijado al Manager; las réplicas de BFF, Requests y Catalog se distribuyen entre
ambos nodos. Eureka, Crews y Report tienen una réplica fijada al Manager para
dejar más memoria al Worker de 4 GiB. Solo se publica el puerto del BFF.
Eureka, MySQL y las APIs de dominio permanecen en la red privada del stack.

```text
Cliente permitido por Security Group
                │
                ▼
          BFF :8080 (2 réplicas)
       ┌────────┼────────┬────────┐
       ▼        ▼        ▼        ▼
   Requests   Catalog   Crews    Report
       │        ▲
       └────────┘ REST por Eureka
            │
    MySQL (Manager)
```

El stack está en [`docker-stack.aws.yml`](./docker-stack.aws.yml) y no contiene
`build`. Las imágenes Java se descargan desde ECR; MySQL usa la imagen oficial
`mysql:8.4`. Cada repositorio de servicio tiene su propio SHA, por lo que se
usan `BFF_IMAGE_TAG`, `CATALOG_IMAGE_TAG`, `REQUESTS_IMAGE_TAG`,
`CREWS_IMAGE_TAG`, `REPORT_IMAGE_TAG` y `EUREKA_IMAGE_TAG` en lugar de una
etiqueta global. `latest` es un fallback; para despliegues reproducibles,
configura cada variable con el SHA publicado por el workflow de ese
componente.

El límite de memoria agregado de los servicios es aproximadamente 5.25 GiB en
el Manager (incluido MySQL) y 2.25 GiB en el Worker, antes de contar el sistema
operativo. Las réplicas dobles de BFF, Requests y Catalog usan `spread` y un
máximo de una réplica por nodo.

### Requisitos y red

- Docker Engine con un Swarm activo, un Manager y al menos un Worker listo.
- AWS CLI configurado con una sesión vigente autorizada para STS y ECR.
- Permisos ECR de pull y repositorios para las seis imágenes en `us-east-1`.
- Secretos Swarm `barriodigital_db_password` y
  `barriodigital_db_app_password` creados en el Manager.
- Security Group: permitir el puerto del BFF solo desde los clientes
  autorizados. No abrir MySQL `3306`, Eureka `8761` ni puertos de dominio.
  Los puertos de control y overlay de Swarm deben permitirse solo entre los
  nodos del clúster.
- `JWT_JWK_SET_URI` y `JWT_ISSUER_URI` HTTPS del User Pool, `JWT_CLIENT_ID` del
  app client y origins HTTPS concretos en `CORS_ALLOWED_ORIGINS`. Los valores
  Cognito del ejemplo corresponden al User Pool configurado; los origins de
  ejemplo deben reemplazarse. La autenticación JWT permanece habilitada.

La autenticación AWS debe estar disponible en el entorno del Manager; no guardes
access keys en `.env.aws`. El script consulta la cuenta con STS, deriva
`ECR_REGISTRY` como `<account-id>.dkr.ecr.<region>.amazonaws.com` y valida
cualquier valor que se haya configurado manualmente.

### Variables

Parte de [`.env.example`](./.env.example) y crea un archivo privado
`.env.aws` en este repositorio. El `.gitignore` excluye `.env.*` excepto el
ejemplo. El script exige recibir el archivo explícitamente; Docker Stack no
carga automáticamente `.env`.

| Variable | Requisito | Uso |
|---|---|---|
| `AWS_REGION` | Opcional; `us-east-1` por defecto | STS/ECR |
| `ECR_REGISTRY` | Opcional; el script la deriva y comprueba | Registry de la cuenta activa |
| `BFF_IMAGE_TAG`, `CATALOG_IMAGE_TAG`, `REQUESTS_IMAGE_TAG`, `CREWS_IMAGE_TAG`, `REPORT_IMAGE_TAG`, `EUREKA_IMAGE_TAG` | SHA recomendado; `latest` por defecto | Tag independiente por repositorio |
| `JWT_JWK_SET_URI` | Obligatoria; HTTPS del User Pool | Validación de firma JWT |
| `JWT_ISSUER_URI` | Obligatoria; HTTPS del User Pool | Validación del claim `iss` |
| `JWT_CLIENT_ID` | Obligatoria; app client ID de Cognito | Validación de access tokens |
| `CORS_ALLOWED_ORIGINS` | Obligatoria; origins HTTPS separados por coma | CORS del BFF |
| `BFF_PORT` | Opcional; `8080` por defecto | Único puerto publicado |
| `EUREKA_SERVER_URL` | Opcional; `http://eureka:8761/eureka/` | Registro de los clientes |
| `REQUESTS_SERVICE_URL`, `CATALOG_SERVICE_URL`, `CREWS_SERVICE_URL`, `REPORT_SERVICE_URL` | Opcionales; IDs lógicos por defecto | Resolución de servicios vía Eureka |
| `HTTP_CONNECT_TIMEOUT`, `HTTP_READ_TIMEOUT` | Opcionales; `2s` y `5s` | Timeouts HTTP |

El stack utiliza los secretos Swarm para las credenciales de MySQL; no se
incluyen contraseñas de base de datos en el archivo de variables.

### Preparar secretos (solo si no existen)

Ejecuta estos comandos en el Manager. Introduce cada valor en el prompt; no se
imprime ni se guarda en el archivo de configuración. Si ya hay datos en el
volumen, los valores deben coincidir con las credenciales con las que se creó
esa base.

```bash
if ! docker secret inspect barriodigital_db_password >/dev/null 2>&1; then
  read -r -s -p 'MySQL root password: ' DB_ROOT_PASSWORD
  printf '\n'
  printf '%s' "$DB_ROOT_PASSWORD" | docker secret create barriodigital_db_password -
  unset DB_ROOT_PASSWORD
fi

if ! docker secret inspect barriodigital_db_app_password >/dev/null 2>&1; then
  read -r -s -p 'MySQL application password: ' DB_APP_PASSWORD
  printf '\n'
  printf '%s' "$DB_APP_PASSWORD" | docker secret create barriodigital_db_app_password -
  unset DB_APP_PASSWORD
fi
```

### Desplegar y comprobar

Desde `barriodigital-infra` en el Manager:

```bash
cp .env.example .env.aws
chmod 600 .env.aws
${EDITOR:-vi} .env.aws
```

Verifica `JWT_JWK_SET_URI`, `JWT_ISSUER_URI` y `JWT_CLIENT_ID`; reemplaza
`CORS_ALLOWED_ORIGINS` y asigna los SHA de cada workflow a sus variables de
tag. Luego ejecuta:

```bash
aws sts get-caller-identity
docker node ls
./scripts/deploy-aws.sh --env-file .env.aws
```

`deploy-aws.sh` comprueba AWS CLI, Docker, el estado de Manager y al menos dos
nodos Ready; valida la configuración; verifica los secretos; inicia sesión en
ECR y despliega con `docker stack deploy --with-registry-auth`. Es idempotente
para las actualizaciones del stack y no elimina servicios de datos, secretos ni
volúmenes. No se ejecutó el despliegue AWS durante la preparación de estos
archivos.

Verificación manual:

```bash
docker stack services barriodigital
docker stack ps barriodigital --no-trunc
curl http://localhost:8080/actuator/health
```

Consulta logs de servicios:

```bash
docker service logs --tail 100 barriodigital_bff
docker service logs --tail 100 barriodigital_requests
docker service logs --tail 100 barriodigital_mysql
```

Escalado manual de servicios stateless:

```bash
docker service scale barriodigital_bff=3
docker service ps barriodigital_bff
```

Las réplicas deseadas están declaradas en el YAML; una futura ejecución del
script vuelve a aplicar esos valores. MySQL no debe escalarse: el volumen local
se fija al Manager y no ofrece failover ni almacenamiento compartido.

Para detener el stack sin borrar datos:

```bash
docker stack rm barriodigital
docker volume ls --filter name=barriodigital_mysql_data
```

`docker stack rm` detiene y elimina los servicios del stack, pero no elimina el
volumen nombrado. No ejecutes `docker volume rm` ni `docker volume prune` si
debes conservar la base de datos.

## AWS y CI/CD

Este repositorio prepara un despliegue manual desde el Manager. No implementa
SQS, Lambda, API Gateway ni despliegue remoto desde GitHub Actions. La
integración de esos componentes queda fuera del alcance de este despliegue.

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
