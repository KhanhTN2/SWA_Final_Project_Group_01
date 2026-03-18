resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${local.name_prefix}-vpc-link"
  security_group_ids = [aws_security_group.apigw_vpc_link.id]
  subnet_ids         = values(aws_subnet.private)[*].id
  tags               = local.common_tags
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.order_api.id]
    issuer   = local.cognito_issuer_uri
  }
}

resource "aws_apigatewayv2_integration" "order" {
  api_id                 = aws_apigatewayv2_api.http.id
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  connection_type        = "VPC_LINK"
  integration_method     = "ANY"
  integration_type       = "HTTP_PROXY"
  integration_uri        = aws_lb_listener.order_http.arn
  payload_format_version = "1.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "post_orders" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /orders"
  target             = "integrations/${aws_apigatewayv2_integration.order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  authorization_scopes = [
    "${aws_cognito_resource_server.orders.identifier}/write"
  ]
}

resource "aws_apigatewayv2_route" "get_order" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /orders/{orderId}"
  target             = "integrations/${aws_apigatewayv2_integration.order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  authorization_scopes = [
    "${aws_cognito_resource_server.orders.identifier}/read"
  ]
}

resource "aws_apigatewayv2_route" "get_product" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /product/{productNumber}"
  target             = "integrations/${aws_apigatewayv2_integration.order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  authorization_scopes = [
    "${aws_cognito_resource_server.orders.identifier}/read"
  ]
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.order.arn
    format = jsonencode({
      requestId = "$context.requestId"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
      ip        = "$context.identity.sourceIp"
    })
  }

  tags = local.common_tags
}
