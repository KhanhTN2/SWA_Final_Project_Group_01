# Migration Decisions

## Decision Summary

| Area | Decision | Rationale | Tradeoff |
| --- | --- | --- | --- |
| Service count | Keep 3 services | Matches the required demo architecture without adding a BFF layer | Less separation at the public edge than a 4-service design |
| Domain migration | Refactor product flow into order flow, retain product catalog table | Preserves existing business data while adding the required order demo | Some class/package history remains from the original service |
| Inventory storage | Keep in-memory inventory | Minimal code, easy demo, visible circuit-breaker behavior | Not durable across restarts |
| REST client | Replace OpenFeign with Spring `RestClient` | Removes Spring Cloud dependency from the runtime path | Less declarative than Feign |
| Security | JWT resource server only on `order-service` | Keeps internal services simple and private | Internal service auth is network-based, not token-based |
| Config | Env vars + typed properties everywhere, AppConfig override loader in `order-service` | Minimal change, AWS-ready, still local-dev friendly | AppConfig integration is startup-time, not dynamic refresh |
| Messaging | Kafka with MSK-compatible config and Redpanda locally | Keeps async flow simple and cloud-aligned | Local and AWS auth modes differ |
| Database | Keep PostgreSQL contract, use minimal RDS PostgreSQL in AWS | Least code change from current JPA model | Adds one managed database to the demo |
| Tracing | Micrometer tracing + OTLP export | Works with the CloudWatch agent OTLP receiver and X-Ray cleanly | Requires sidecar wiring in ECS |

## Old To New Mapping

| Old component or assumption | New implementation |
| --- | --- |
| `product-service` | `order-service` |
| `stock-service` | `inventory-service` |
| direct `stock.service.url` config | `INVENTORY_SERVICE_BASE_URL` with ECS/Docker service name |
| Spring Cloud OpenFeign | Spring `RestClient` |
| stale Consul environment variables | removed |
| no event flow | `OrderCreatedEvent` over Kafka |
| no JWT handling | Cognito-compatible OAuth2 resource server |

## Assumptions

- Spring Boot remains on `3.2.3`
- Java remains on `17`
- AWS profile is activated explicitly with `SPRING_PROFILES_ACTIVE=aws`
- Cognito issuer URI and audience are provided at deploy time
- Cognito custom scopes are `orders/read` and `orders/write`
- AppConfig agent is available in ECS when AppConfig overrides are enabled
- API Gateway integrates privately to the Cloud Map registration used by the `order-service`

## Manual Follow-Ups

- Replace the demo Redpanda image flow with ECR-hosted images in AWS
- Create one Cognito user or hosted UI flow for demo authentication
- Load initial product catalog rows if the AWS database is empty and SQL init is disabled
- Supply MSK bootstrap brokers, Cognito values, and database secrets through Terraform variables or CI/CD secrets
- Validate the included AWS AppConfig agent and CloudWatch agent sidecars in the deployed ECS tasks before the demo
