output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = module.school_app.api_gateway_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.school_app.rds_endpoint
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.school_app.lambda_function_name
}
