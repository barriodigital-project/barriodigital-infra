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

### Ejecución local

Requisitos: JDK 21. No es necesario instalar Maven: `eureka-server` incluye
Maven Wrapper y descargará Maven 3.10.0 la primera vez que se ejecute.
Los comandos siguientes asumen que PowerShell parte desde la carpeta raíz del
workspace. Define Java 21 solo en la terminal actual (ajusta la ruta si el JDK
está instalado en otro lugar):

```powershell
$env:JAVA_HOME = 'D:\Program Files\Java\jdk-21.0.10'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
java -version
```

Ejecuta cada servicio en una terminal distinta y mantén sus procesos activos.
Si se usan los valores predeterminados de los microservicios, MySQL debe estar
disponible en `localhost:3306` y sus bases de datos deben existir.

1. Inicia Eureka:

   ```powershell
   cd barriodigital-infra\eureka-server
   .\mvnw.cmd spring-boot:run
   ```

   La consola queda disponible en <http://localhost:8761/>. El servidor no se
   registra a sí mismo ni consulta otro registro.

   Para ejecutar pruebas:

   ```powershell
   .\mvnw.cmd test
   ```

2. Inicia Catalog:

   ```powershell
   cd ms-barriodigital-catalog
   .\mvnw.cmd spring-boot:run
   ```

   Catalog escucha en `http://localhost:8082` y se registra como `catalog-ms`.

3. Inicia Requests:

   ```powershell
   cd ms-barriodigital-requests
   .\mvnw.cmd spring-boot:run
   ```

   Requests escucha en `http://localhost:8081` y se registra como `request-ms`.
   Ambos clientes usan `EUREKA_SERVER_URL`, cuyo valor predeterminado es
   `http://localhost:8761/eureka/`. Requests utiliza Spring Cloud LoadBalancer
   con el nombre lógico `http://catalog-ms`, resuelto desde Eureka.

En el panel de Eureka deben aparecer `CATALOG-MS` y `REQUEST-MS`. Para comprobar
que Requests descubre Catalog, se puede usar el flujo que consulta la
disponibilidad del tipo de trámite; la llamada de Requests a `catalog-ms` será
resuelta por el registro, sin configurar una URL fija. La interfaz REST de
Eureka también está disponible en `http://localhost:8761/eureka/apps`.

### VS Code

Abre la carpeta `barriodigital-infra\eureka-server` con **File > Open Folder**.
VS Code importa el proyecto Maven desde `pom.xml`; instala **Extension Pack for
Java** si se solicita. La configuración de esta carpeta selecciona Java 21 y
define el perfil **Run Eureka Server** en **Run and Debug**. También se puede
usar **Run** sobre el método `main` una vez que termine la importación Maven.
La ruta del JDK del archivo `.vscode/settings.json` debe existir en el equipo;
si es diferente, actualiza allí el valor de `java.configuration.runtimes`.
No abras ni ejecutes solamente `EurekaServerApplication.java` como archivo
Java suelto: eso evita que VS Code resuelva las dependencias de Spring. Si el
archivo aparece como *non-project*, ejecuta **Java: Import Java Projects in
Workspace** desde la paleta de comandos y espera a que finalice la importación
de Maven antes de pulsar **Run**.

Para levantarlo desde el terminal integrado de VS Code, establece `JAVA_HOME` y
`Path` en esa terminal como se mostró arriba y ejecuta `.\mvnw.cmd
spring-boot:run`. Esas variables solo afectan a la terminal actual y no cambian
el `PATH` global de Windows.

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
