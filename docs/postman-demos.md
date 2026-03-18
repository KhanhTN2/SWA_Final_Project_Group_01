# Postman Demo Collections

The repo now includes Postman assets for the demo scenarios in [`docs/demo-scenario.md`](./demo-scenario.md).

Files:

- [`postman/aws-modernized-demo.postman_environment.json`](../postman/aws-modernized-demo.postman_environment.json)
- [`postman/aws-modernized-demo-api.postman_collection.json`](../postman/aws-modernized-demo-api.postman_collection.json)
- [`postman/aws-modernized-demo-ops.postman_collection.json`](../postman/aws-modernized-demo-ops.postman_collection.json)

## What Each Collection Covers

- `aws-modernized-demo-api`: API Gateway requests for Demo 1 happy path, Demo 2 failover flow, Demo 3 circuit-breaker open calls, and Demo 3 recovery calls
- `aws-modernized-demo-ops`: ECS scale/stop operations plus CloudWatch Logs lookups used around those demos

## Import And Setup

1. Import the environment and both collections into Postman.
2. Select the `AWS Modernized Demo (us-east-2)` environment.
3. Set `access_token` in the environment before using the API collection.
4. Set `aws_access_key_id`, `aws_secret_access_key`, and optionally `aws_session_token` before using the ops collection.

The checked-in environment already contains the current stack values for:

- API Gateway base URL
- Cognito Hosted UI base URL
- Cognito app client ID
- ECS cluster and service names
- log group names
- ALB target group ARN

It intentionally does not include AWS credentials or an API bearer token.

## Access Token

The API collection expects a bearer token in `{{access_token}}`.

The simplest manual flow in Postman is:

1. Open the Cognito Hosted UI base URL from `{{cognito_hosted_ui_base_url}}`
2. Authenticate as `demo-user`
3. Obtain an access token with scopes:
   `openid email profile orders/read orders/write`
4. Paste that token into the `access_token` environment variable

The demo user created by the helper scripts defaults to:

- username: `demo-user`
- password: `DemoPassw0rd!`

## AWS Ops Auth

The ops collection uses AWS Signature Version 4 per request.

Populate these environment variables before running it:

- `aws_access_key_id`
- `aws_secret_access_key`
- `aws_session_token` if your credentials are temporary

## Recommended Run Order

Demo 1:

1. Run the `Demo 1 - Happy Path` folder in the API collection
2. Run the `Order Logs By Demo 1 Correlation` and `Notification Logs By Demo 1 Correlation` requests in the ops collection

Demo 2:

1. Run `Scale Inventory To 2`
2. Run `List Inventory Tasks`
3. Run `Stop Captured Inventory Task`
4. Run the `Demo 2 - Inventory Failover` folder in the API collection
5. Run `Order Logs By Demo 2 Correlation`

Demo 3 open:

1. Run `Scale Inventory To 0`
2. Run the `Demo 3 - Circuit Breaker Open` folder in the API collection
3. Run `Order Logs - Breaker Events`
4. Run `Notification Logs - Notification Processed`

Demo 3 recovery:

1. Run `Scale Inventory Back To 2`
2. Wait about 12 seconds
3. Run the `Demo 3 - Circuit Breaker Recovery` folder in the API collection
4. Optionally run `Order Logs - Breaker Events` again to confirm transition logs
5. Run `Scale Inventory Back To 1` if you want to return to the normal baseline

## Notes

- The API collection stores created order IDs back into environment variables so the lookup requests can be run directly after create
- The ops collection stores the first running `inventory-service` task ARN into `inventory_task_to_stop`
- CloudWatch Logs filtering in Postman is less expressive than the shell `grep -E` examples, so some log requests use narrower phrase filters or one correlation ID at a time
