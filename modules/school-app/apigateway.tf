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
  payload_format_version = "2.0"
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
