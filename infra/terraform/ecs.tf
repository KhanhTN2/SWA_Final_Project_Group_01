resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${local.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task_access" {
  name = "${local.name_prefix}-ecs-task-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt",
          "appconfig:StartConfigurationSession",
          "appconfig:GetLatestConfiguration",
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:WriteDataIdempotently",
          "xray:PutTelemetryRecords",
          "xray:PutTraceSegments"
        ]
        Resource = [
          aws_msk_serverless_cluster.events.arn,
          "*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData"
        ]
        Resource = [
          "${local.msk_topic_arn_prefix}/${var.order_created_topic}",
          "${local.msk_transactional_id_arn_prefix}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = [
          "${local.msk_group_arn_prefix}/*"
        ]
      }
    ]
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "order" {
  family                   = "${local.name_prefix}-order-service"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "appconfig-agent"
      image     = "public.ecr.aws/aws-appconfig/aws-appconfig-agent:latest"
      essential = true
      environment = [
        { name = "SERVICE_REGION", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.order.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "appconfig"
        }
      }
    },
    {
      name      = "cloudwatch-agent"
      image     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest"
      essential = true
      secrets = [
        { name = "CW_CONFIG_CONTENT", valueFrom = aws_ssm_parameter.cloudwatch_agent_config.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.order.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cwagent"
        }
      }
    },
    {
      name      = "order-service"
      image     = var.order_service_image
      essential = true
      dependsOn = [
        { containerName = "appconfig-agent", condition = "START" },
        { containerName = "cloudwatch-agent", condition = "START" }
      ]
      portMappings = [{
        name          = "http"
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "aws" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.order.address}:5432/${var.db_name}" },
        { name = "KAFKA_BOOTSTRAP_SERVERS", value = local.kafka_bootstrap },
        { name = "INVENTORY_SERVICE_BASE_URL", value = "http://inventory-service:8080" },
        { name = "ORDER_CREATED_TOPIC", value = var.order_created_topic },
        { name = "COGNITO_ISSUER_URI", value = local.cognito_issuer_uri },
        { name = "COGNITO_AUDIENCE", value = aws_cognito_user_pool_client.order_api.id },
        { name = "APP_SECURITY_ENABLED", value = "true" },
        { name = "APPCONFIG_ENABLED", value = "true" },
        { name = "APPCONFIG_BASE_URL", value = "http://localhost:2772" },
        { name = "APPCONFIG_RESOURCE_PATH", value = local.appconfig_path },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4317" }
      ]
      secrets = [
        { name = "SPRING_DATASOURCE_USERNAME", valueFrom = aws_ssm_parameter.db_username.arn },
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.order.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "inventory" {
  family                   = "${local.name_prefix}-inventory-service"
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "cloudwatch-agent"
      image     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest"
      essential = true
      secrets = [
        { name = "CW_CONFIG_CONTENT", valueFrom = aws_ssm_parameter.cloudwatch_agent_config.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.inventory.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cwagent"
        }
      }
    },
    {
      name      = "inventory-service"
      image     = var.inventory_service_image
      essential = true
      dependsOn = [
        { containerName = "cloudwatch-agent", condition = "START" }
      ]
      portMappings = [{
        name          = "http"
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "aws" },
        { name = "APP_INVENTORY_FAIL_MODE", value = "false" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4317" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.inventory.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "notification" {
  family                   = "${local.name_prefix}-notification-service"
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "cloudwatch-agent"
      image     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest"
      essential = true
      secrets = [
        { name = "CW_CONFIG_CONTENT", valueFrom = aws_ssm_parameter.cloudwatch_agent_config.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.notification.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cwagent"
        }
      }
    },
    {
      name      = "notification-service"
      image     = var.notification_service_image
      essential = true
      dependsOn = [
        { containerName = "cloudwatch-agent", condition = "START" }
      ]
      portMappings = [{
        name          = "http"
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
        appProtocol   = "http"
      }]
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "aws" },
        { name = "KAFKA_BOOTSTRAP_SERVERS", value = local.kafka_bootstrap },
        { name = "ORDER_CREATED_TOPIC", value = var.order_created_topic },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4317" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.notification.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "order" {
  name            = "order-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.order.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.public)[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.order.arn
    port         = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.services.arn

    service {
      port_name      = "http"
      discovery_name = "order-service-sc"

      client_alias {
        dns_name = "order-service"
        port     = 8080
      }
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "inventory" {
  name            = "inventory-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.inventory.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.public)[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.inventory.arn
    port         = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.services.arn

    service {
      port_name      = "http"
      discovery_name = "inventory-service-sc"

      client_alias {
        dns_name = "inventory-service"
        port     = 8080
      }
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "notification" {
  name            = "notification-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.notification.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = values(aws_subnet.public)[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.notification.arn
    port         = 8080
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.services.arn

    service {
      port_name      = "http"
      discovery_name = "notification-service-sc"

      client_alias {
        dns_name = "notification-service"
        port     = 8080
      }
    }
  }

  tags = local.common_tags
}
