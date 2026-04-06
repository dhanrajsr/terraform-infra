# ─── IAM Role for Lambda ──────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "school-lambda-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "school-lambda-s3-${var.environment}"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::${var.lambda_jar_bucket}/*"
    }]
  })
}

# ─── Lambda Function ──────────────────────────────────────────
resource "aws_lambda_function" "school_api" {
  function_name = "school-api-${var.environment}"
  role          = aws_iam_role.lambda.arn

  s3_bucket = var.lambda_jar_bucket
  s3_key    = var.lambda_jar_key

  runtime     = "java21"
  handler     = "com.school.api.StreamLambdaHandler::handleRequest"
  memory_size = 512
  timeout     = 30           # Spring Boot cold start needs time

  environment {
    variables = {
      DB_URL      = "jdbc:postgresql://${aws_db_instance.school.endpoint}/${var.db_name}"
      DB_USERNAME = var.db_username
      DB_PASSWORD = var.db_password
      SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
    }
  }

  tags = merge(var.tags, { Name = "school-api-${var.environment}" })
}

# ─── Lambda Permission for API Gateway ────────────────────────
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.school_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.school.execution_arn}/*/*"
}
