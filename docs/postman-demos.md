# Postman Demo Collections

The repo now includes Postman assets for the demo scenarios in [`docs/demo-scenario.md`](./demo-scenario.md).

Files:

- [`postman/aws-modernized-demo.postman_environment.json`](../postman/aws-modernized-demo.postman_environment.json)
- [`postman/aws-modernized-demo-api.postman_collection.json`](../postman/aws-modernized-demo-api.postman_collection.json)
- [`postman/aws-modernized-demo-ops.postman_collection.json`](../postman/aws-modernized-demo-ops.postman_collection.json)

## What Each Collection Covers

- `aws-modernized-demo-api`: starts with an `Auth - Get Token` folder for Cognito Hosted UI login, then the API Gateway requests for Demo 1 happy path, Demo 2 failover flow, Demo 3 circuit-breaker open calls, and Demo 3 recovery calls
- `aws-modernized-demo-ops`: ECS scale/stop operations plus CloudWatch Logs lookups used around those demos

## Import And Setup

1. Import the environment and both collections into Postman.
2. Select the `AWS Modernized Demo (us-east-2)` environment.
3. Run the `Auth - Get Token` folder in the API collection before using the demo folders, or manually set `access_token`.
4. Set `aws_access_key_id`, `aws_secret_access_key`, and optionally `aws_session_token` before using the ops collection.

The API collection also carries built-in collection variables for the current demo stack, so the auth flow still works if you forget to select the environment. The environment is still recommended, especially if you want the mutable values visible in one place or you need the ops collection.

The checked-in environment already contains the current stack values for:

- API Gateway base URL
- Cognito Hosted UI base URL
- Cognito app client ID
- ECS cluster and service names
- log group names
- ALB target group ARN

It intentionally does not include AWS credentials or an API bearer token.

## Get Token

The `Auth - Get Token` folder inside the API collection mirrors the working Hosted UI flow already used by `scripts/run-aws-demo.py`.

Run these requests in order:

1. `Hosted UI Login Page`
2. `Hosted UI Login Form`
3. `Exchange Authorization Code`
4. Optional: `Get UserInfo`

The first request intentionally calls Cognito `/login` directly instead of `/oauth2/authorize` so Postman shows the actual login page rather than the empty initial `302` redirect hop.

After `Exchange Authorization Code`, the collection stores:

- `access_token`
- `id_token`
- `refresh_token`
- `access_token_type`
- `access_token_expires_in`

The API collection uses `{{access_token}}` automatically after that.

The demo user created by the helper scripts defaults to:

- username: `demo-user`
- password: `DemoPassw0rd!`

Fallback:

- if you prefer, you can still obtain a token manually and paste it into `access_token`

## AWS Ops Auth

The ops collection uses AWS Signature Version 4 per request.

Populate these environment variables before running it:

- `aws_access_key_id`
- `aws_secret_access_key`
- `aws_session_token` if your credentials are temporary

## Recommended Run Order

Demo 1:

1. Run `Auth - Get Token` first if `access_token` is empty
2. Run the `Demo 1 - Happy Path` folder in the API collection
3. Run the `Order Logs By Demo 1 Correlation` and `Notification Logs By Demo 1 Correlation` requests in the ops collection

Demo 2:

1. Run `Auth - Get Token` first if `access_token` is empty
2. Run `Scale Inventory To 2`
3. Run `List Inventory Tasks`
4. Run `Stop Captured Inventory Task`
5. Run the `Demo 2 - Inventory Failover` folder in the API collection
6. Run `Order Logs By Demo 2 Correlation`

Demo 3 open:

1. Run `Auth - Get Token` first if `access_token` is empty
2. Run `Scale Inventory To 0`
3. Run the `Demo 3 - Circuit Breaker Open` folder in the API collection
4. Run `Order Logs - Breaker Events`
5. Run `Notification Logs - Notification Processed`

Demo 3 recovery:

1. Run `Auth - Get Token` first if `access_token` is empty
2. Run `Scale Inventory Back To 2`
3. Wait about 12 seconds
4. Run the `Demo 3 - Circuit Breaker Recovery` folder in the API collection
5. Optionally run `Order Logs - Breaker Events` again to confirm transition logs
6. Run `Scale Inventory Back To 1` if you want to return to the normal baseline

## Notes

- The API collection stores created order IDs back into environment variables so the lookup requests can be run directly after create
- The ops collection stores the first running `inventory-service` task ARN into `inventory_task_to_stop`
- CloudWatch Logs filtering in Postman is less expressive than the shell `grep -E` examples, so some log requests use narrower phrase filters or one correlation ID at a time
