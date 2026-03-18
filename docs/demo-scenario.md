# Demo Scenario

## Goal

Show the AWS-targeted architecture in one short session:

- authenticated access through API Gateway and Cognito
- synchronous service-to-service REST over ECS Service Connect / Cloud Map
- asynchronous Kafka publish and consume through MSK Serverless
- fallback behavior when `inventory-service` is unavailable

## Pre-Demo Checklist

Export the common shell variables first:

```bash
export AWS_PROFILE=demo
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""
export AWS_DEMO_USERNAME='demo-user'
export AWS_DEMO_PASSWORD='DemoPassw0rd!'
```

If you want a clean environment for every demo, rebuild the stack instead of resuming it:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/rebuild-demo-stack.sh
```

Notes:

- this gives you a fresh API Gateway, Cognito pool, RDS database, and MSK cluster each time
- `scripts/rebuild-demo-stack.sh` runs `destroy-demo-stack.sh`, `apply-demo-stack.sh`, and `recreate-demo-user.sh` in order
- `scripts/destroy-demo-stack.sh` saves the image URIs it used into `.destroy-demo-images.env`, and `apply-demo-stack.sh` reuses that file automatically
- this flow is slower than `resume-demo.sh`, but it is the cleanest repeatable demo path

If the stack was only parked, resume it instead:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/resume-demo.sh
```

Confirm the key live endpoints:

```bash
terraform -chdir=infra/terraform output api_gateway_endpoint
terraform -chdir=infra/terraform output cognito_hosted_ui_base_url
terraform -chdir=infra/terraform output ecs_cluster_name
```

If you used the clean rebuild flow, the previous step already recreated the default `demo-user`. If you only resumed the stack, keep using the exported `AWS_DEMO_USERNAME` and `AWS_DEMO_PASSWORD` values from above.

## Demo 1: Happy Path

Run the end-to-end helper with a fixed correlation ID:

```bash
python3 scripts/run-aws-demo.py \
  --correlation-id demo-happy-path-001
```

Expected result:

- `productCheck.status` is `200`
- `orderCreate.status` is `201`
- `orderCreate.body.status` is `RESERVED`
- `orderLookup.status` is `200`
- `productCheck.body.numberOnStock` decreases after repeated runs, which proves the internal reservation call is happening

What to say while this runs:

- the client is calling API Gateway, not the service directly
- Cognito is issuing the JWT used by the helper
- `order-service` is the public backend service behind API Gateway
- `order-service` calls `inventory-service` internally through Service Connect / Cloud Map naming

## Demo 1: Async Proof

Show that the order event was published and consumed by filtering logs with the same correlation ID:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-happy-path-001|Published order-created event'
```

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws logs tail /ecs/aws-modernized-demo/notification-service --since 5m --format short | \
grep -E 'demo-happy-path-001|Notification processed'
```

Expected result:

- `order-service` logs `Published order-created event`
- `notification-service` logs `Notification processed`
- both log streams show the same correlation ID

What this proves:

- REST and persistence completed in `order-service`
- Kafka publication succeeded against MSK Serverless
- `notification-service` consumed the event asynchronously

## Demo 2: Fallback Path

Simulate inventory unavailability by scaling `inventory-service` to zero:

```bash
CLUSTER_NAME=$(terraform -chdir=infra/terraform output -raw ecs_cluster_name)

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 0

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services inventory-service
```

Now run the helper in order-only mode:

```bash
python3 scripts/run-aws-demo.py \
  --skip-product-check \
  --correlation-id demo-fallback-001
```

Expected result:

- `orderCreate.status` is `201`
- `orderCreate.body.status` is `PENDING_INVENTORY`
- `orderCreate.body.message` says the inventory service is unavailable and a fallback order was created
- `orderLookup.status` is `200`

Show that the async event still flows even during fallback:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-fallback-001|Published order-created event'
```

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws logs tail /ecs/aws-modernized-demo/notification-service --since 5m --format short | \
grep -E 'demo-fallback-001|Notification processed'
```

Optional note:

- one failed call is enough to show fallback behavior
- repeated failures will continue to feed the configured Resilience4j circuit breaker state machine in `order-service`

## Restore After Fallback Demo

Bring `inventory-service` back:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 1

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services inventory-service
```

## Visibility Points

- API Gateway access logs show the authenticated edge request
- `order-service` CloudWatch logs show the order creation and Kafka publish
- `notification-service` CloudWatch logs show async event consumption
- X-Ray shows the request trace for the synchronous path
- repeated happy-path calls show stock decreasing, which is an easy visual proof of the internal REST hop

## Troubleshooting

- If `aws logs tail ... | grep -E ...` prints nothing, wait a few seconds and run it again because CloudWatch Logs can lag slightly behind the API response
- If you prefer `rg`, install ripgrep with `brew install ripgrep` and replace `grep -E` in the examples

## End Of Session

If you want to park the stack after the demo:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/pause-demo.sh
```

Reminder:

- `pause-demo.sh` stops ECS services and requests an RDS stop
- MSK Serverless stays billable until the stack is destroyed

If you want to fully tear the demo stack down after the session, use the destroy helper:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/destroy-demo-stack.sh
```

If you want to rebuild the stack from scratch before the next session, use:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-1 \
bash scripts/rebuild-demo-stack.sh
```

Use this when you want the next demo to start from a clean environment. The helper retries `terraform destroy`, bypasses AppConfig deletion protection through the AWS CLI when needed, and cleans up Cloud Map namespace leftovers before retrying. The next session will require `terraform apply` and `bash scripts/recreate-demo-user.sh` before running the demo again.
