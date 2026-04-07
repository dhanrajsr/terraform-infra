# ─── HTTP API Gateway ─────────────────────────────────────────
resource "aws_apigatewayv2_api" "school" {
  name          = "school-api-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = merge(var.tags, { Name = "school-api-${var.environment}" })
}

# ─── Lambda Integration ───────────────────────────────────────
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.school.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.school_api.invoke_arn
  payload_format_version = "1.0"
}

# ─── Catch-all Route → Lambda ─────────────────────────────────
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.school.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ─── Auto-deploy Stage ────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.school.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = var.tags
}

# ─── CloudWatch Log Group ─────────────────────────────────────
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/school-api-${var.environment}"
  retention_in_days = 7

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/school-api-${var.environment}"
  retention_in_days = 7

  tags = var.tags
}

# ─── ACM Certificate for custom domain ───────────────────────
resource "aws_acm_certificate" "api" {
  count             = var.custom_domain != "" ? 1 : 0
  domain_name       = var.custom_domain
  validation_method = "DNS"

  tags = merge(var.tags, { Name = var.custom_domain })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── API Gateway Custom Domain ────────────────────────────────
resource "aws_apigatewayv2_domain_name" "api" {
  count       = var.custom_domain != "" ? 1 : 0
  domain_name = var.custom_domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api[0].arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = merge(var.tags, { Name = var.custom_domain })

  depends_on = [aws_acm_certificate.api]
}

# ─── API Mapping — custom domain → $default stage ─────────────
resource "aws_apigatewayv2_api_mapping" "api" {
  count       = var.custom_domain != "" ? 1 : 0
  api_id      = aws_apigatewayv2_api.school.id
  domain_name = aws_apigatewayv2_domain_name.api[0].id
  stage       = aws_apigatewayv2_stage.default.id
}
