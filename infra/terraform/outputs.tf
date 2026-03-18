output "api_gateway_endpoint" {
  description = "Invoke URL for the HTTP API"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "order_alb_dns_name" {
  description = "DNS name of the internal ALB fronting order-service"
  value       = aws_lb.order.dns_name
}

output "order_target_group_arn" {
  description = "Target group ARN used by order-service"
  value       = aws_lb_target_group.order.arn
}

output "order_service_image" {
  description = "Container image URI currently used for order-service"
  value       = var.order_service_image
}

output "inventory_service_image" {
  description = "Container image URI currently used for inventory-service"
  value       = var.inventory_service_image
}

output "notification_service_image" {
  description = "Container image URI currently used for notification-service"
  value       = var.notification_service_image
}

output "ecs_cluster_name" {
  description = "ECS cluster name for the demo services"
  value       = aws_ecs_cluster.main.name
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = aws_cognito_user_pool.order_users.id
}

output "cognito_app_client_id" {
  description = "Cognito app client ID"
  value       = aws_cognito_user_pool_client.order_api.id
}

output "cognito_user_pool_domain" {
  description = "Cognito hosted auth domain"
  value       = aws_cognito_user_pool_domain.order_api.domain
}

output "cognito_hosted_ui_base_url" {
  description = "Base URL for the Cognito hosted UI"
  value       = "https://${aws_cognito_user_pool_domain.order_api.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_issuer_uri" {
  description = "Issuer URI used by API Gateway and order-service"
  value       = local.cognito_issuer_uri
}

output "cloud_map_namespace_name" {
  description = "Cloud Map namespace used by ECS Service Connect"
  value       = aws_service_discovery_private_dns_namespace.services.name
}

output "order_service_discovery_arn" {
  description = "Cloud Map service ARN for order-service"
  value       = aws_service_discovery_service.order.arn
}

output "appconfig_application_name" {
  description = "AppConfig application name"
  value       = aws_appconfig_application.runtime.name
}

output "appconfig_runtime_path" {
  description = "AppConfig agent resource path used by order-service"
  value       = local.appconfig_path
}

output "db_endpoint" {
  description = "RDS endpoint for order-service"
  value       = aws_db_instance.order.address
}

output "db_instance_identifier" {
  description = "RDS instance identifier for order-service"
  value       = aws_db_instance.order.identifier
}

output "msk_cluster_arn" {
  description = "MSK Serverless cluster ARN"
  value       = aws_msk_serverless_cluster.events.arn
}

output "msk_bootstrap_brokers_note" {
  description = "MSK bootstrap brokers used by the ECS tasks"
  value       = local.kafka_bootstrap
}
