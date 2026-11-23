# Pendientes de AWS y CI/CD

**Estado:** planificación únicamente. No se crearon recursos AWS, workflows,
credenciales ni despliegues remotos durante la preparación local.

## 1. Orden recomendado de implementación

1. **Definir decisiones de plataforma:** región, entorno, estrategia de alta
   disponibilidad, gestor de secretos, base MySQL, API Gateway REST/HTTP y
   destino final de contenedores. El stack actual es una demostración Swarm de
   un nodo; no es una arquitectura cloud de alta disponibilidad.
2. **Infraestructura base como código:** VPC, subredes privadas/públicas,
   rutas, NAT/endpoints necesarios, DNS, certificados y security groups.
   Limitar los puertos de Swarm entre nodos y no publicar APIs de dominio.
3. **Identidad de ejecución:** roles IAM para EC2 y Lambda y rol federado
   GitHub Actions mediante OIDC. No crear usuarios IAM con claves permanentes
   para pipelines.
4. **Registro de imágenes:** repositorios ECR por servicio activo
   (BFF, Requests, Catalog, Crews, Report y Eureka), políticas de retención,
   escaneo y etiquetas por commit/release.
5. **Cómputo y operación:** instancias EC2 privadas administradas por Systems
   Manager, con estrategia documentada de manager/worker, actualizaciones,
   backups y recuperación. Si Swarm multinodo deja de ser requisito, evaluar
   ECS como alternativa gestionada antes de provisionar.
6. **Base de datos:** decidir entre una instancia MySQL administrada con
   esquemas/usuarios separados o instancias separadas. Definir backups,
   cifrado, recuperación a un punto en el tiempo, rotación y conectividad
   privada. No usar root desde microservicios.
7. **Secretos y parámetros:** Secrets Manager/Parameter Store para credenciales
   MySQL, secretos JWT si aplican y URLs de servicios. El valor local
   `DB_PASSWORD` no se debe copiar a cloud.
8. **Notificaciones SQS/Lambda:** crear cola y DLQ, política de retención,
   cifrado, Lambda Java, event source mapping, alarmas y permisos mínimos.
   Acordar primero el contrato/payload y la semántica de reintentos.
9. **Identidad de usuarios y entrada:** configurar Cognito, grupos/roles, API
   Gateway con authorizer JWT, rutas al BFF, throttling, TLS, CORS y logs.
   El BFF debe validar el issuer/audience adecuados y recibir el JWKS real.
10. **Observabilidad y continuidad:** CloudWatch logs, métricas, alarmas,
    dashboards, alertas, trazas, procedimientos de rollback y pruebas de
    restauración.
11. **CI/CD e IaC:** pipelines por repositorio o un pipeline central; build,
    tests, análisis, generación/escaneo de imágenes, publicación ECR y
    despliegue controlado con aprobación. Gestionar IaC en un repositorio
    separado o dentro de infraestructura, con estado remoto protegido.

## 2. Dependencias entre recursos

```text
VPC/subredes/security groups
   ├── EC2/Swarm y acceso privado a MySQL
   ├── API Gateway → BFF
   └── Lambda → SQS

IAM/OIDC ──► ECR ──► EC2/Swarm (pull de imágenes)
    │                   └──► CloudWatch/Secrets Manager
    └──► GitHub Actions (publicación y despliegue restringidos)

Cognito ──► API Gateway JWT authorizer ──► BFF ──► microservicios
SQS/DLQ ──► Lambda (notificaciones; diseño futuro)
MySQL administrado ──► Requests, Catalog, Crews, Report
```

Red y roles preceden al cómputo; la base/secretos deben existir antes de
conectar los servicios; ECR antes de desplegar contenedores. Cognito/API Gateway
y SQS/Lambda se pueden construir en paralelo después de acordar los contratos,
pero no se debe declarar el flujo completo hasta probarlo integrado.

## 3. Variables futuras

Nombres sugeridos; valores y formato deben confirmarse en la implementación:

| Grupo | Variables/valores a definir |
|---|---|
| Entorno | `AWS_REGION`, nombre de entorno, IDs/ARN gestionados por IaC. |
| Base de datos | `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, referencia a secreto; idealmente usuario/schema por servicio. |
| Service discovery | URL/base de Eureka o reemplazo elegido; IDs de servicio y dominios privados. |
| BFF/identidad | `JWT_JWK_SET_URI`, issuer/audience, `CORS_ALLOWED_ORIGINS`, URLs de dependencias. |
| Notificaciones | `SQS_QUEUE_URL`, región, tamaño/límite de lote, timeout y política de reintentos. |
| Operación | nombres de log groups, niveles de log, endpoints de health y etiquetas de release. |
| CI/CD | nombres/ARN de roles OIDC, repositorios ECR, ambiente de aprobación y destino de despliegue. |

No usar valores de ejemplo como credenciales ni subir secretos a repositorios.

## 4. Permisos IAM mínimos a diseñar

- **Instancia EC2:** autenticación/pull limitado desde ECR, envío de logs y
  lectura de secretos requeridos por los servicios; acceso SSM. Sin permisos
  administrativos generales.
- **Lambda:** recibir/borrar mensajes de una cola concreta, escribir logs y
  leer solo los secretos estrictamente necesarios. No permitir acceso amplio a
  todas las colas.
- **GitHub Actions:** rol OIDC condicionado al repositorio, branch/tag y
  ambiente; permisos limitados a build/push de ECR y despliegue de servicios
  autorizados. No usar claves largas guardadas como variables.
- **API Gateway/Cognito:** permisos mínimos para validar tokens y enrutar al
  BFF. Los servicios internos no deben quedar públicos.
- **Base de datos:** separar credenciales de aplicación y administración;
  mantener acceso de red privado y restringir por security group.

Los nombres concretos, trust policies y ARNs deben generarse por IaC y
revisarse antes de aplicar.

## 5. Componentes que requieren cambios futuros

- **Requests:** definir eventos/acciones de notificación y cuándo publicarlos;
  usar outbox o mecanismo confiable si no se puede perder la notificación.
- **SQS/Lambda:** implementar productor/consumer real, idempotencia, DLQ,
  redrive, límites, observabilidad y contrato versionado. No forma parte del
  backend local actual.
- **Report:** definir una fuente verificable de `RequestReport`. No poblar
  datos con métricas simuladas ni añadir un broker solo para este servicio.
- **BFF:** configurar issuer/audience y JWKS reales, API Gateway, CORS y
  variables cloud; preservar roles por ruta.
- **Servicios con JPA:** retirar `ddl-auto=update` en ambientes persistentes y
  adoptar migraciones; usar cuentas de BD de mínimo privilegio.
- **Infra:** elegir ECR/EC2/Swarm o cambiar explícitamente a un orquestador
  gestionado; IaC, TLS, DNS, backups, logs, alarmas y procedimiento de rollback.
- **Contratos:** especificar payload SQS/Lambda después de decidir la interfaz;
  mantenerlo marcado como futuro mientras no exista implementación.

## 6. Repositorios y workflows futuros

Repositorios independientes observados:

- `ms-barriodigital-bff`
- `ms-barriodigital-requests`
- `ms-barriodigital-catalog`
- `ms-barriodigital-crews`
- `ms-barriodigital-report`
- `barriodigital-infra`
- `barriodigital-contracts`

Audit y Notify no son parte de la arquitectura elegida. Sus repositorios se
mantienen limpios; el traslado físico al archivo hermano está pendiente por un
bloqueo de Windows. Cuando se habilite CI, cada repositorio activo necesitará
al menos build/test; repositorios de aplicaciones además necesitan build/scan
de imagen; infraestructura necesita validación de Compose/Stack/IaC y
despliegue protegido. Contracts necesita validación de OpenAPI y revisión de
cambios incompatibles. **No se crearon workflows en esta fase.**

## 7. Pruebas cloud pendientes

- Autenticación de API Gateway con JWT Cognito, roles, issuer/audience inválidos,
  CORS, throttling y rutas no autorizadas.
- Conectividad privada BFF→servicios y servicios→MySQL; rotación de secretos.
- Pull ECR desde nodos sin credenciales permanentes.
- Pruebas SQS/Lambda de duplicados, orden, timeout, retry, DLQ y redrive.
- Reportería con datos reales provenientes de una fuente de eventos definida.
- Rolling update, rollback, pérdida de nodo, recuperación de base y restore de
  backup.
- Métricas/logs/alarms y costo bajo carga.
- Prueba de escalado entre nodos y persistencia real multinodo.

## 8. Estado de evaluación EP3

No se proporcionó la rúbrica que define los indicadores IE1–IE17. No es
responsable asignarles cumplimiento individual sin conocer su criterio ni la
evidencia exigida. Se deben mapear uno a uno cuando se disponga de esa rúbrica;
las demostraciones de AWS, multi-nodo o video permanecen pendientes hasta
ejecutarse y grabarse.
