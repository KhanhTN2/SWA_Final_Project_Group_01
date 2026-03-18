# Deploy To AWS

## What Terraform Provisions

The Terraform under `infra/terraform/` is structured to provision:

- VPC, subnets, internet gateway, route tables
- ECS cluster
- Cloud Map namespace
- ECS task definitions and services
- Service Connect configuration
- API Gateway HTTP API and JWT authorizer
- Cognito user pool and app client
- CloudWatch log groups
- IAM roles and policies
- MSK Serverless cluster
- SSM parameters and Secrets Manager placeholders
- a minimal single-AZ PostgreSQL RDS instance

## Prerequisites

- AWS CLI authenticated to the target account
- Terraform installed
- container images pushed to ECR
- a target AWS region selected

## Suggested Deployment Flow

1. Build and push images:

```bash
docker build -t <ecr>/order-service:latest code/order-service
docker build -t <ecr>/inventory-service:latest code/inventory-service
docker build -t <ecr>/notification-service:latest code/notification-service
```

2. Initialize and apply Terraform:

```bash
cd infra/terraform
terraform init
terraform apply \
  -var "aws_region=us-east-1" \
  -var "order_service_image=<ecr>/order-service:latest" \
  -var "inventory_service_image=<ecr>/inventory-service:latest" \
  -var "notification_service_image=<ecr>/notification-service:latest"
```

3. Wait for the first ECS deployment to finish. `order-service` now creates the `orders.created` topic through Kafka admin APIs and seeds the demo catalog into PostgreSQL if the catalog is empty.
4. Create at least one Cognito user or use the hosted UI domain returned by Terraform outputs to obtain an access token with the `orders/read` and `orders/write` scopes.
5. Confirm ECS tasks are healthy and Cloud Map registrations exist.
6. Invoke the HTTP API URL returned by Terraform outputs with a Cognito token, or use the checked-in demo helper:

```bash
AWS_PROFILE=demo \
AWS_DEFAULT_REGION=us-east-1 \
AWS_DEMO_USERNAME='<cognito-username>' \
AWS_DEMO_PASSWORD='<cognito-password>' \
python3 scripts/run-aws-demo.py
```

## Clean Rebuild Between Demo Sessions

If you want a fresh environment for each demo instead of pausing the existing one, start with the common shell variables:

```bash
export AWS_PROFILE=demo
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""
export AWS_DEMO_USERNAME='demo-user'
export AWS_DEMO_PASSWORD='DemoPassw0rd!'
```

The simplest end-to-end reset is:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/rebuild-demo-stack.sh
```

If you want to run the steps separately, destroy first:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/destroy-demo-stack.sh
```

Then reapply with the same image inputs saved by the destroy step:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/apply-demo-stack.sh
```

Recreate the Cognito demo user after the new user pool exists:

```bash
bash scripts/recreate-demo-user.sh
```

Then validate the fresh stack:

```bash
python3 scripts/run-aws-demo.py --correlation-id demo-clean-reset-001
```

Notes:

- `terraform destroy` removes the previous Cognito pool, RDS data, MSK cluster, and CloudWatch history for the demo stack
- `scripts/destroy-demo-stack.sh` wraps `terraform destroy` and handles the current AWS provider gap around AppConfig deletion protection plus Cloud Map namespace cleanup
- `scripts/destroy-demo-stack.sh` writes `.destroy-demo-images.env`, and `scripts/apply-demo-stack.sh` loads it automatically
- `scripts/rebuild-demo-stack.sh` is the safest one-command reset path because it chains destroy, apply, and user recreation
- `scripts/recreate-demo-user.sh` recreates `demo-user` with the password stored in `AWS_DEMO_PASSWORD`, or `DemoPassw0rd!` if that variable is unset
- this is the lowest-risk way to get a clean demo state every time

## Runtime Configuration Inputs

Set these values through Terraform variables, SSM, or Secrets Manager:

- Cognito issuer URI
- Cognito app client audience
- Cognito custom scopes `orders/read` and `orders/write`
- RDS username and password
- MSK bootstrap brokers if different from Terraform-created outputs
- optional AppConfig application/environment/profile path values

## Sidecars And AWS Integrations

The ECS task definitions now include:

- AWS AppConfig agent on `localhost:2772` for `order-service`
- CloudWatch agent on `localhost:4317` as an OTLP receiver that forwards traces to X-Ray

After deployment, verify both sidecars are healthy in the ECS task view before exercising the demo.

## Manual Checks After Deploy

- API Gateway route integrates to the Cloud Map-backed `order-service`
- `order-service` can resolve `inventory-service` over Service Connect
- `notification-service` consumes from the `orders.created` topic after the first `order-service` startup creates it
- CloudWatch log groups receive JSON logs
- X-Ray shows traces from `order-service` and `inventory-service`
- `python3 scripts/run-aws-demo.py` completes with `GET /product`, `POST /orders`, and `GET /orders/{orderId}` all succeeding

## Pause And Resume For Demo Day

Pause the stack between sessions:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/pause-demo.sh
```

Resume the stack before the next session:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/resume-demo.sh
```

Notes:

- `pause-demo.sh` saves the current ECS desired counts into `.demo-day-state.env`, scales `order-service`, `inventory-service`, and `notification-service` to zero, and requests an RDS stop
- `resume-demo.sh` restores the saved desired counts and waits for RDS to be available before bringing the ECS services back
- MSK Serverless is not paused by these scripts and remains billable until you destroy the stack
