# AWS Target Architecture

## Current State

The original backend was a two-service Spring Boot demo:

- `product-service`: PostgreSQL-backed product lookup with a synchronous stock call
- `stock-service`: in-memory stock endpoint
- local Docker Compose only
- no JWT security, Kafka, tracing, JSON logging, or infrastructure as code

## Target State

The backend now targets a minimal AWS-native microservice design:

- `order-service`: public application service behind Amazon API Gateway
- `inventory-service`: internal ECS service discovered through ECS Service Connect and AWS Cloud Map
- `notification-service`: Kafka consumer for order-created events
- Amazon ECS Fargate for runtime
- Amazon API Gateway HTTP API for the external edge
- Amazon Cognito for user authentication and JWT issuance
- Amazon MSK Serverless for Kafka
- Amazon CloudWatch Logs for centralized logs
- AWS X-Ray through OpenTelemetry export to a CloudWatch agent sidecar
- AWS AppConfig, SSM Parameter Store, and Secrets Manager for externalized config
- PostgreSQL-compatible database contract retained for least code change, deployed as minimal RDS PostgreSQL in AWS

## Service Responsibilities

### order-service

- Exposes primary public paths `POST /orders` and `GET /orders/{orderId}` behind API Gateway
- Retains `/api/orders` and `/api/product/{productNumber}` as compatibility aliases inside the service
- Exposes `GET /product/{productNumber}` for the current API Gateway compatibility route
- Validates Cognito-compatible JWTs when the `aws` profile is active
- Expects Cognito custom scopes `orders/read` and `orders/write`
- Calls `inventory-service` synchronously over internal DNS
- Publishes `OrderCreatedEvent` to Kafka
- Uses Resilience4j to fall back to `PENDING_INVENTORY` when inventory is unavailable

### inventory-service

- Exposes internal-only inventory APIs
- Serves current stock availability
- Handles stock reservation requests
- Supports a simple fail mode for circuit-breaker demos

### notification-service

- Consumes `OrderCreatedEvent`
- Logs a simulated notification action in structured JSON

## Runtime Flow

### Synchronous flow

1. Client calls API Gateway `POST /orders`
2. API Gateway validates JWT from Cognito
3. API Gateway forwards traffic privately to `order-service`
4. `order-service` calls `inventory-service` through the ECS Service Connect name `inventory-service`
5. `order-service` persists the order and returns the API response

### Asynchronous flow

1. `order-service` publishes `OrderCreatedEvent` to Kafka on MSK Serverless
2. `notification-service` consumes the event
3. `notification-service` logs the notification outcome to stdout
4. ECS sends container logs to CloudWatch Logs

## Current-to-Target Component Mapping

| Previous assumption | AWS target |
| --- | --- |
| direct container URL / stale Consul assumptions | ECS Service Connect + Cloud Map |
| public ALB-only edge notes | API Gateway HTTP API |
| no auth | Cognito + API Gateway JWT authorizer + Spring resource server |
| local-only config | AppConfig + Parameter Store + Secrets Manager |
| no tracing | OpenTelemetry -> CloudWatch agent OTLP receiver -> X-Ray |
| plain console logs | JSON stdout -> CloudWatch Logs |
| no messaging | MSK Serverless Kafka |

## Local Development Strategy

- `docker-compose.local.yml` starts Postgres, Redpanda, `order-service`, `inventory-service`, and `notification-service`
- local profile disables JWT enforcement by default for practical developer startup
- service discovery uses Docker DNS with the same logical service names used in ECS
- Kafka uses Redpanda locally and MSK Serverless in AWS

## Cloud Deployment Strategy

- Build each service image and push to ECR
- Provision AWS resources from `infra/terraform/`
- Deploy each service as an ECS Fargate service with Cloud Map registration and Service Connect enabled
- Inject config via task environment, SSM parameters, and Secrets Manager
- ECS task definitions include an AppConfig agent sidecar for `order-service` and a CloudWatch agent sidecar for OTLP-to-X-Ray export
- Route public traffic through API Gateway to `order-service`
- Keep `inventory-service` and `notification-service` private inside the VPC
