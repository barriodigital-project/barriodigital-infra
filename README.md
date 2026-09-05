# barriodigital-infra

Repositorio de infraestructura y despliegue de **BarrioDigital**.

## Responsabilidades

- Configuración Docker.
- Docker Compose.
- MySQL.
- RabbitMQ.
- Kafka.
- Eureka.
- AWS.
- Configuración de despliegue.
- Variables de entorno.
- Scripts de infraestructura.

## Tecnologías

- Docker
- Docker Compose
- MySQL
- RabbitMQ
- Apache Kafka
- Eureka
- AWS API Gateway
- Amazon Cognito
- Amazon ECR
- AWS EC2
- AWS Secrets Manager
- Amazon CloudWatch
- GitHub Actions

## Arquitectura

```text
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

## Servicios

```text
ms-barriodigital-bff
ms-barriodigital-requests
ms-barriodigital-catalog
ms-barriodigital-crews
ms-barriodigital-notify
ms-barriodigital-audit
ms-barriodigital-report
```

## Puertos

```text
4200  → Angular

8080  → BFF
8081  → Requests
8082  → Catalog
8083  → Crews
8084  → Notify
8086  → Audit
8087  → Report

8761  → Eureka

3306  → MySQL

5672  → RabbitMQ
15672 → RabbitMQ Management

9092  → Kafka
```

## Bases de datos

```text
barriodigital_requests_db
barriodigital_catalog_db
barriodigital_crews_db
barriodigital_audit_db
barriodigital_report_db
```

Cada microservicio mantiene propiedad exclusiva de su base de datos.

## RabbitMQ

```text
q.cmd.notification
q.cmd.crew
```

Productor:

```text
Requests
```

Consumidor:

```text
Notify
```

## Kafka

Tópico:

```text
requests.events
```

Productor:

```text
Requests
```

Consumidores:

```text
Audit
Report
```

Consumer Groups:

```text
barriodigital-audit-group
barriodigital-report-group
```

## Service Registry

```text
Eureka
```

Puerto:

```text
8761
```

## Resiliencia

```text
Resilience4j
```

Utilizado para Circuit Breaker en comunicaciones REST críticas.

## Seguridad

### Amazon Cognito

- OAuth 2.0.
- OpenID Connect.
- JWT.
- Roles y grupos.

### AWS API Gateway

- Punto de entrada.
- Routing.
- Validación de JWT.

### AWS Secrets Manager

- Credenciales.
- Contraseñas.
- Secretos.

## Observabilidad

```text
Spring Boot Actuator
Amazon CloudWatch
```

Se monitorearán principalmente:

- API Gateway.
- BFF.
- Requests.
- RabbitMQ.
- Kafka.
- Bases de datos.

## Despliegue

```text
GitHub
   ↓
GitHub Actions
   ↓
Docker
   ↓
Amazon ECR
   ↓
AWS EC2
   ↓
Docker Compose
```

## Estructura esperada

```text
barriodigital-infra/
│
├── README.md
│
├── docker/
│   ├── compose.yml
│   ├── mysql/
│   ├── rabbitmq/
│   ├── kafka/
│   └── eureka/
│
├── aws/
│   ├── api-gateway/
│   ├── cognito/
│   ├── ec2/
│   ├── ecr/
│   ├── cloudwatch/
│   └── secrets-manager/
│
├── scripts/
│
└── env/
    └── .env.example
```

## Variables de entorno

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

Los secretos reales no deben versionarse.

## Ambientes

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

## Estado

🚧 Infraestructura en etapa inicial de implementación.
