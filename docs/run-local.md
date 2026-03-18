# Run Local

## Prerequisites

- Docker Desktop or equivalent Docker runtime
- ports `5432`, `8081`, `8082`, `8083`, and `19092` available

## Start The Stack

```bash
docker compose -f docker-compose.local.yml up --build
```

## Local Endpoints

- `order-service`: `http://localhost:8081`
- `inventory-service`: `http://localhost:8082`
- `notification-service`: `http://localhost:8083`
- Redpanda Kafka bootstrap: `localhost:19092`
- PostgreSQL: `localhost:5432`

## Example Requests

Compatibility read:

```bash
curl http://localhost:8081/api/product/PROD001
```

Create an order:

```bash
curl -X POST http://localhost:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"productNumber":"PROD001","quantity":2}'
```

Fetch an order:

```bash
curl http://localhost:8081/api/orders/{orderId}
```

## Trigger The Fallback Path

Stop the inventory service and then create another order:

```bash
docker compose -f docker-compose.local.yml stop inventory-service
curl -X POST http://localhost:8081/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"productNumber":"PROD002","quantity":1}'
```

Expected behavior:

- the order is still created
- the response status field becomes `PENDING_INVENTORY`
- `notification-service` still logs the order-created event

## Useful Commands

View service logs:

```bash
docker compose -f docker-compose.local.yml logs -f order-service inventory-service notification-service
```

Shut everything down:

```bash
docker compose -f docker-compose.local.yml down -v
```
