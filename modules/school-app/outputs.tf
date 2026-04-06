output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.school.endpoint
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.school_api.function_name
}
