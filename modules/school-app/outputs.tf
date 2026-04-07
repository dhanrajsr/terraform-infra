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

output "acm_validation_record" {
  description = "DNS CNAME record to add for ACM certificate validation"
  value = var.custom_domain != "" ? {
    name  = tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.api[0].domain_validation_options)[0].resource_record_value
  } : null
}

output "api_gateway_domain_target" {
  description = "CNAME target to point school-api.devopscab.com to API Gateway"
  value       = var.custom_domain != "" ? aws_apigatewayv2_domain_name.api[0].domain_name_configuration[0].target_domain_name : null
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.school.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito App Client ID (used in React Amplify config)"
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_hosted_ui_domain" {
  description = "Cognito Hosted UI domain"
  value       = "https://${aws_cognito_user_pool_domain.school.domain}.auth.${var.region}.amazoncognito.com"
}
