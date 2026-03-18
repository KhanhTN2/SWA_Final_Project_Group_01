CREATE TABLE IF NOT EXISTS products (
    product_number VARCHAR(50)  PRIMARY KEY,
    name           VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    order_id        VARCHAR(36) PRIMARY KEY,
    product_number  VARCHAR(50)  NOT NULL,
    product_name    VARCHAR(255) NOT NULL,
    quantity        INTEGER      NOT NULL,
    status          VARCHAR(50)  NOT NULL,
    message         VARCHAR(1000),
    correlation_id  VARCHAR(100),
    created_at      TIMESTAMP    NOT NULL
);
