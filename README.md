# barriodigital-infra

Repositorio de infraestructura, configuración de ambientes y despliegue de la plataforma **BarrioDigital**.

## Descripción

Este repositorio centraliza los elementos necesarios para ejecutar e integrar los componentes de BarrioDigital en ambientes locales y cloud.

No contiene lógica de negocio.

## Responsabilidades

- Docker Compose.
- Configuración de infraestructura local.
- Configuración de MySQL.
- Configuración de RabbitMQ.
- Configuración de Kafka.
- Configuración de Eureka.
- Configuración de servicios AWS.
- Scripts de despliegue.
- Configuración de redes.
- Variables de entorno de ejemplo.
- Documentación operacional.

## Tecnologías

- Docker
- Docker Compose
- AWS
- AWS EC2
- Amazon ECR
- Amazon Cognito
- AWS API Gateway
- AWS Secrets Manager
- Amazon CloudWatch
- MySQL
- RabbitMQ
- Apache Kafka
- Eureka
- GitHub Actions

## Arquitectura de despliegue inicial

```text
Internet
   ↓
Angular
   ↓
Amazon Cognito
   ↓
AWS API Gateway
   ↓
BFF
   ↓
Microservicios
   ↓
MySQL / RabbitMQ / Kafka
```

Los componentes backend serán ejecutados inicialmente mediante:

```text
AWS EC2
+
Docker
+
Docker Compose
```

## Estructura esperada

```text
barriodigital-infra/
│
├── README.md
│
├── docker/
│   ├── apps/
│   │   └── compose.yml
│   │
│   ├── mysql/
│   │   └── compose.yml
│   │
│   ├── rabbitmq/
│   │   └── compose.yml
│   │
│   ├── kafka/
│   │   └── compose.yml
│   │
│   └── platform/
│       └── compose.yml
│
├── aws/
│   ├── ec2/
│   ├── ecr/
│   ├── cognito/
│   ├── api-gateway/
│   ├── cloudwatch/
│   └── security-groups/
│
├── scripts/
│   ├── local/
│   └── deploy/
│
├── env/
│   └── .env.example
│
└── docs/
```

## Servicios backend

Los servicios considerados son:

```text
ms-barriodigital-bff
ms-barriodigital-requests
ms-barriodigital-catalog
ms-barriodigital-crews
ms-barriodigital-notify
ms-barriodigital-documents
ms-barriodigital-audit
ms-barriodigital-report
```

## Puertos locales

Asignación inicial:

```text
8080  → BFF
8081  → Requests
8082  → Catalog
8083  → Crews
8084  → Notify
8085  → Documents
8086  → Audit
8087  → Report
```

Infraestructura:

```text
8761  → Eureka

3306  → MySQL

5672  → RabbitMQ AMQP
15672 → RabbitMQ Management UI

9092  → Kafka
```

Estos valores podrán modificarse mediante variables de entorno.

## MySQL

Se utilizará el patrón:

```text
Database per Service
```

Bases iniciales:

```text
barriodigital_requests_db
barriodigital_catalog_db
barriodigital_crews_db
barriodigital_audit_db
barriodigital_report_db
```

Aunque inicialmente puedan compartir una instancia MySQL durante desarrollo, cada microservicio mantendrá propiedad lógica exclusiva sobre su base.

## RabbitMQ

Flujos considerados:

```text
q.cmd.email
q.cmd.crew
q.cmd.certificate
```

DLQ:

```text
q.cmd.email.dlq
q.cmd.crew.dlq
q.cmd.certificate.dlq
```

Exchanges:

```text
cmd.direct
cmd.topic
cmd.dead.dlx
```

Puertos:

```text
5672
15672
```

## Kafka

Tópicos considerados:

```text
requests.events
audit.timeline
*.DLT
```

Puerto:

```text
9092
```

Kafka será utilizado principalmente para:

- eventos de dominio;
- auditoría;
- reportería;
- analítica.

## Service Discovery

Se utilizará inicialmente:

```text
Spring Cloud Netflix Eureka
```

Puerto:

```text
8761
```

## Resiliencia

Los microservicios utilizarán:

```text
Resilience4j
```

para patrones como:

- Circuit Breaker.
- Timeout.
- Retry.

## AWS

### Amazon Cognito

Responsable de:

- autenticación;
- OAuth 2.0;
- OpenID Connect;
- JWT;
- roles/grupos.

### AWS API Gateway

Responsable de:

- punto único de entrada;
- validación JWT;
- routing;
- políticas de acceso.

### AWS EC2

Utilizado para ejecutar los componentes de la solución mediante Docker.

### Amazon ECR

Repositorio de imágenes Docker.

Flujo:

```text
GitHub Actions
      ↓
Docker Build
      ↓
Amazon ECR
      ↓
AWS EC2
```

### AWS Secrets Manager

Utilizado para almacenar información sensible como:

- credenciales;
- passwords;
- tokens;
- secrets.

### Amazon CloudWatch

Utilizado para:

- logs;
- métricas;
- alertas;
- monitoreo.

## Docker Compose

Durante desarrollo se utilizará Docker Compose para simplificar el levantamiento de dependencias.

La idea es permitir ejecutar:

```bash
docker compose up -d
```

para levantar los servicios requeridos por el ambiente correspondiente.

## Variables de entorno

Nunca se deberán versionar secretos reales.

Se utilizará:

```text
.env.example
```

Ejemplo:

```env
MYSQL_HOST=
MYSQL_PORT=3306
MYSQL_USER=
MYSQL_PASSWORD=

RABBITMQ_HOST=
RABBITMQ_PORT=5672
RABBITMQ_USER=
RABBITMQ_PASSWORD=

KAFKA_BOOTSTRAP_SERVERS=

EUREKA_SERVER_URL=

AWS_REGION=
```

Los archivos:

```text
.env
```

deberán permanecer fuera de Git.

## CI/CD

La infraestructura trabajará junto con pipelines de GitHub Actions.

Flujo general:

```text
Push / Pull Request
        ↓
Build
        ↓
Tests
        ↓
SonarQube
        ↓
Snyk
        ↓
Docker Build
        ↓
Amazon ECR
        ↓
AWS EC2
```

## Seguridad

La infraestructura debe considerar:

- HTTPS/TLS.
- JWT.
- RBAC.
- Security Groups.
- Secrets Manager.
- Principio de mínimo privilegio.
- Puertos mínimos necesarios.
- Servicios internos no expuestos públicamente.

## Observabilidad

Se considera:

- Amazon CloudWatch.
- Spring Boot Actuator.
- Logs estructurados.
- Health checks.
- Métricas.
- Monitoreo de RabbitMQ.
- Monitoreo de Kafka.
- Seguimiento de DLQ/DLT.

## Ambientes

Inicialmente se consideran:

```text
local
development
production
```

Durante el desarrollo académico, el foco principal será:

```text
local
development
```

## Estrategia Git

```text
main
develop
feature/*
fix/*
```

## Relación con otros repositorios

### Aplicaciones

```text
frontend-barriodigital
ms-barriodigital-*
```

### Contratos

```text
barriodigital-contracts
```

Este repositorio no define contratos funcionales.

Su responsabilidad se limita a infraestructura y despliegue.

## Estado

🚧 Infraestructura en etapa inicial de diseño y construcción.
