resource "aws_cloudwatch_log_group" "order" {
  name              = "/ecs/${local.name_prefix}/order-service"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "inventory" {
  name              = "/ecs/${local.name_prefix}/inventory-service"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "notification" {
  name              = "/ecs/${local.name_prefix}/notification-service"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_service_discovery_private_dns_namespace" "services" {
  name = local.cloud_map_namespace
  vpc  = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_service_discovery_service" "order" {
  name = "order-service"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.services.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "SRV"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "inventory" {
  name = "inventory-service"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.services.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "SRV"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "notification" {
  name = "notification-service"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.services.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "SRV"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}:?."
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name_prefix}/db/password"
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_ssm_parameter" "db_username" {
  name  = "${local.ssm_path_prefix}/db/username"
  type  = "String"
  value = var.db_username
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "order_created_topic" {
  name  = "${local.ssm_path_prefix}/order-created-topic"
  type  = "String"
  value = var.order_created_topic
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name = "${local.ssm_path_prefix}/observability/cloudwatch-agent-config"
  type = "String"
  value = jsonencode({
    traces = {
      traces_collected = {
        otlp = {
          grpc_endpoint = "0.0.0.0:4317"
          http_endpoint = "0.0.0.0:4318"
        }
      }
    }
  })
  tags = local.common_tags
}

resource "aws_appconfig_application" "runtime" {
  name        = "${local.name_prefix}-runtime"
  description = "Runtime configuration for the AWS modernization demo"
  tags        = local.common_tags
}

resource "aws_appconfig_environment" "demo" {
  application_id = aws_appconfig_application.runtime.id
  name           = "demo"
  description    = "Demo environment"
  tags           = local.common_tags
}

resource "aws_appconfig_configuration_profile" "runtime" {
  application_id = aws_appconfig_application.runtime.id
  location_uri   = "hosted"
  name           = "runtime"
  type           = "AWS.Freeform"
}

resource "aws_appconfig_hosted_configuration_version" "runtime" {
  application_id           = aws_appconfig_application.runtime.id
  configuration_profile_id = aws_appconfig_configuration_profile.runtime.configuration_profile_id
  content                  = local.appconfig_json
  content_type             = "application/json"
}

resource "aws_appconfig_deployment_strategy" "all_at_once" {
  name                           = "${local.name_prefix}-all-at-once"
  deployment_duration_in_minutes = 0
  final_bake_time_in_minutes     = 0
  growth_factor                  = 100
  replicate_to                   = "NONE"
}

resource "aws_appconfig_deployment" "runtime" {
  application_id           = aws_appconfig_application.runtime.id
  configuration_profile_id = aws_appconfig_configuration_profile.runtime.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.runtime.version_number
  deployment_strategy_id   = aws_appconfig_deployment_strategy.all_at_once.id
  environment_id           = aws_appconfig_environment.demo.environment_id
  description              = "Initial runtime configuration"
}

resource "aws_cognito_user_pool" "order_users" {
  name = "${local.name_prefix}-users"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    mutable             = true
    name                = "email"
    required            = true

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "order_api" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.order_users.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes = [
    "email",
    "openid",
    "profile",
    "${aws_cognito_resource_server.orders.identifier}/read",
    "${aws_cognito_resource_server.orders.identifier}/write"
  ]
  explicit_auth_flows          = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  supported_identity_providers = ["COGNITO"]
  generate_secret              = false
  callback_urls                = ["https://example.com/callback"]
  logout_urls                  = ["https://example.com/logout"]
}

resource "aws_cognito_resource_server" "orders" {
  identifier   = "orders"
  name         = "${local.name_prefix}-orders-api"
  user_pool_id = aws_cognito_user_pool.order_users.id

  scope {
    scope_name        = "read"
    scope_description = "Read order and product data"
  }

  scope {
    scope_name        = "write"
    scope_description = "Create orders"
  }
}

resource "aws_cognito_user_pool_domain" "order_api" {
  domain       = local.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.order_users.id
}

resource "aws_msk_serverless_cluster" "events" {
  cluster_name = "${local.name_prefix}-msk"

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = values(aws_subnet.private)[*].id
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = local.common_tags
}

data "aws_msk_bootstrap_brokers" "events" {
  cluster_arn = aws_msk_serverless_cluster.events.arn
}

resource "aws_db_subnet_group" "order" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = values(aws_subnet.private)[*].id
  tags       = local.common_tags
}

resource "aws_db_instance" "order" {
  identifier              = "${local.name_prefix}-postgres"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  max_allocated_storage   = 100
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.order.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 0
  multi_az                = false
  auto_minor_version_upgrade = true
  storage_encrypted       = true
  tags                    = local.common_tags
}
