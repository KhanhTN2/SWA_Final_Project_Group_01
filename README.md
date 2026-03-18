# AWS-Modernized Spring Boot Microservices Demo

Software Architecture final project for modernizing a small Spring Boot backend into an AWS-targeted microservice demo.

## Overview

The project is split into three services:

- `order-service`: public API that creates and reads orders
- `inventory-service`: internal dependency for stock lookup and reservation
- `notification-service`: Kafka consumer for order-created events

The AWS target architecture uses:

- Amazon ECS Fargate
- Amazon API Gateway HTTP API
- Amazon Cognito
- Amazon MSK Serverless
- Amazon RDS for PostgreSQL
- Amazon CloudWatch Logs
- AWS X-Ray through OpenTelemetry export
- AWS AppConfig, SSM Parameter Store, and Secrets Manager

For local development, the repository uses Docker Compose with PostgreSQL and Redpanda instead of the AWS-managed services.

## Repository Layout

- `code/`: Spring Boot services
- `infra/terraform/`: Terraform for the AWS target environment
- `scripts/`: demo lifecycle, deploy, pause, resume, and destroy helpers
- `docs/`: architecture, deployment, local run, and demo guides
- `docker-compose.local.yml`: local development stack

## Run Locally

Prerequisites:

- Docker Desktop or another Docker runtime
- ports `5432`, `8081`, `8082`, `8083`, and `19092` available

Start the local stack from the repository root:

```bash
docker compose -f docker-compose.local.yml up --build
```

Local endpoints:

- `order-service`: `http://localhost:8081`
- `inventory-service`: `http://localhost:8082`
- `notification-service`: `http://localhost:8083`
- Redpanda Kafka bootstrap: `localhost:19092`
- PostgreSQL: `localhost:5432`

Example requests:

```bash
curl http://localhost:8081/api/product/PROD001
```

```bash
curl -X POST http://localhost:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"productNumber":"PROD001","quantity":2}'
```

```bash
curl http://localhost:8081/api/orders/{orderId}
```

To exercise the fallback path locally:

```bash
docker compose -f docker-compose.local.yml stop inventory-service
curl -X POST http://localhost:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"productNumber":"PROD002","quantity":1}'
```

Useful local commands:

```bash
docker compose -f docker-compose.local.yml logs -f order-service inventory-service notification-service
```

```bash
docker compose -f docker-compose.local.yml down -v
```

More detail: [docs/run-local.md](docs/run-local.md)

## AWS Demo Workflow

Authenticate the AWS CLI before using the deploy or demo scripts.

### AWS CLI Login: 2 Ways

#### 1. IAM Identity Center / AWS SSO (recommended)

Use this if your AWS account is managed through your organization.

```bash
aws configure sso --profile demo
aws sso login --profile demo
aws sts get-caller-identity --profile demo
```

If the AWS CLI cannot open a browser, use device code flow during setup:

```bash
aws configure sso --use-device-code --profile demo
```

#### 2. Access key and secret key

Use this if you were given an IAM user's access key pair.

```bash
aws configure --profile demo
aws sts get-caller-identity --profile demo
```

Typical values during `aws configure`:

- `AWS Access Key ID`: your IAM access key
- `AWS Secret Access Key`: your IAM secret key
- `Default region name`: `us-east-2`
- `Default output format`: `json`

Export the common demo variables first:

```bash
export AWS_PROFILE=demo
export AWS_DEFAULT_REGION=us-east-2
export AWS_PAGER=""
export AWS_DEMO_USERNAME='demo-user'
export AWS_DEMO_PASSWORD='DemoPassw0rd!'
```

Fresh demo environment:

```bash
bash scripts/rebuild-demo-stack.sh
```

Run the live AWS demo:

```bash
python3 scripts/run-aws-demo.py --correlation-id demo-happy-path-001
```

Pause an existing demo stack between sessions:

```bash
bash scripts/pause-demo.sh
```

Resume a paused demo stack:

```bash
bash scripts/resume-demo.sh
```

Destroy the demo stack:

```bash
bash scripts/destroy-demo-stack.sh
```

Generated state files used by the helper scripts:

- `.demo-day-state.env`: saved ECS desired counts and RDS identifiers for pause/resume
- `.destroy-demo-images.env`: saved image URIs reused by apply and rebuild flows

More detail: [docs/deploy-aws.md](docs/deploy-aws.md) and [docs/demo-scenario.md](docs/demo-scenario.md)

## Documentation

- [docs/aws-architecture-diagram.md](docs/aws-architecture-diagram.md)
- [docs/aws-target-architecture.md](docs/aws-target-architecture.md)
- [docs/migration-decisions.md](docs/migration-decisions.md)
- [docs/run-local.md](docs/run-local.md)
- [docs/deploy-aws.md](docs/deploy-aws.md)
- [docs/demo-scenario.md](docs/demo-scenario.md)
