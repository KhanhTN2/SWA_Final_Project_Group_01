# Demo Scenario

## Goal

Show the AWS-targeted architecture in one short session:

- authenticated access through API Gateway and Cognito
- synchronous service-to-service REST over ECS Service Connect / Cloud Map
- inventory replica failover when one `inventory-service` task stops
- asynchronous Kafka publish and consume through MSK Serverless
- circuit-breaker fallback behavior when `inventory-service` is unavailable

## Pre-Demo Checklist

Export the common shell variables first:

```bash
export AWS_PROFILE=demo
export AWS_DEFAULT_REGION=us-east-2
export AWS_PAGER=""
export AWS_DEMO_USERNAME='demo-user'
export AWS_DEMO_PASSWORD='DemoPassw0rd!'
```

If you want a clean environment for every demo, rebuild the stack instead of resuming it:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
bash scripts/rebuild-demo-stack.sh
```

Notes:

- this gives you a fresh API Gateway, Cognito pool, RDS database, and MSK cluster each time
- `scripts/rebuild-demo-stack.sh` runs `destroy-demo-stack.sh`, `apply-demo-stack.sh`, and `recreate-demo-user.sh` in order
- `scripts/destroy-demo-stack.sh` saves the image URIs it used into `.destroy-demo-images.env`, and `apply-demo-stack.sh` reuses that file automatically
- this flow is slower than `resume-demo.sh`, but it is the cleanest repeatable demo path

If the stack was only parked, resume it instead:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
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
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-happy-path-001|Published order-created event'
```

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
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

## Demo 2: Inventory Instance Failover

This is a normal-success demo. It proves service-to-service failover, not circuit breaking. The current circuit breaker should stay closed because one healthy `inventory-service` task remains available the whole time.

Scale `inventory-service` to two tasks first:

```bash
CLUSTER_NAME=$(terraform -chdir=infra/terraform output -raw ecs_cluster_name)

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 2

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services inventory-service

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name inventory-service \
  --query 'taskArns' \
  --output text
```

Stop one of the two running inventory tasks:

```bash
INVENTORY_TASK_TO_STOP=$(
  AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
  aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name inventory-service \
    --query 'taskArns[0]' \
    --output text
)

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs stop-task \
  --cluster "$CLUSTER_NAME" \
  --task "$INVENTORY_TASK_TO_STOP" \
  --reason "demo one inventory replica stopped"
```

Now run the standard end-to-end flow:

```bash
python3 scripts/run-aws-demo.py \
  --correlation-id demo-failover-001
```

Expected result:

- `productCheck.status` is `200`
- `orderCreate.status` is `201`
- `orderCreate.body.status` is `RESERVED`
- `orderLookup.status` is `200`
- the user-visible flow still works normally because Service Connect / Cloud Map routes to the remaining healthy inventory task

Show the difference between failover and CB by checking the `order-service` logs:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-failover-001|Circuit breaker inventoryService'
```

What this proves:

- stopping one replica does not break the user flow
- this is ECS + Service Connect failover across inventory tasks
- if one healthy inventory task remains, the circuit breaker should stay closed
- Demo 2 is intentionally not the breaker demo

## Demo 3: Circuit Breaker Open + Fallback

This is the only breaker/fallback demo in the sequence.

Simulate inventory unavailability by scaling `inventory-service` to zero:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 0

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services inventory-service
```

Trigger enough failed calls to open the breaker. The current configuration in `order-service` uses a count window of `5`, needs at least `3` calls, and opens when failures reach `50%`.

```bash
for i in 1 2 3 4; do
  python3 scripts/run-aws-demo.py \
    --skip-product-check \
    --correlation-id "demo-cb-open-00${i}"
done
```

Expected result:

- each request still returns `201`, so the demo remains user-visible
- `orderCreate.body.status` is `PENDING_INVENTORY`
- after the repeated failures, `order-service` logs `Circuit breaker inventoryService state transition CLOSED_TO_OPEN`
- the later calls are short-circuited and log `Circuit breaker inventoryService rejected a call because it is OPEN`

Show that the breaker actually opened and that the async event still flows:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-cb-open-|Published order-created event|Circuit breaker inventoryService'
```

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws logs tail /ecs/aws-modernized-demo/notification-service --since 5m --format short | \
grep -E 'demo-cb-open-|Notification processed'
```

What this proves:

- fallback responses alone do not prove an open breaker
- the `CLOSED_TO_OPEN` and `rejected a call because it is OPEN` log lines are the proof
- the order flow and Kafka event publication still continue while the downstream inventory service is unavailable
- Demo 3, not Demo 2, is where breaker behavior is intentionally demonstrated

## Restore After Circuit Breaker Demo

Bring `inventory-service` back:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 2

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services inventory-service
```

Wait slightly longer than the configured open-state duration, then send two healthy requests so the breaker can transition through half-open back to closed:

```bash
sleep 12

python3 scripts/run-aws-demo.py \
  --correlation-id demo-cb-recover-001

python3 scripts/run-aws-demo.py \
  --correlation-id demo-cb-recover-002
```

Confirm recovery:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws logs tail /ecs/aws-modernized-demo/order-service --since 5m --format short | \
grep -E 'demo-cb-recover-|Circuit breaker inventoryService'
```

Expected recovery log sequence:

- `Circuit breaker inventoryService state transition OPEN_TO_HALF_OPEN`
- `Circuit breaker inventoryService state transition HALF_OPEN_TO_CLOSED`

If you want to return to the normal baseline after the demo, scale `inventory-service` back to one task:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service inventory-service \
  --desired-count 1

AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
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
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
bash scripts/pause-demo.sh
```

Reminder:

- `pause-demo.sh` stops ECS services and requests an RDS stop
- MSK Serverless stays billable until the stack is destroyed

If you want to fully tear the demo stack down after the session, use the destroy helper:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
bash scripts/destroy-demo-stack.sh
```

If you want to rebuild the stack from scratch before the next session, use:

```bash
AWS_PROFILE=demo AWS_DEFAULT_REGION=us-east-2 \
bash scripts/rebuild-demo-stack.sh
```

Use this when you want the next demo to start from a clean environment. The helper retries `terraform destroy`, bypasses AppConfig deletion protection through the AWS CLI when needed, and cleans up Cloud Map namespace leftovers before retrying. The next session will require `terraform apply` and `bash scripts/recreate-demo-user.sh` before running the demo again.
