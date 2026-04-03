output "role_arn" {
  description = "IAM Role ARN to set as AWS_ROLE_ARN GitHub Secret"
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket" {
  description = "S3 bucket name for Terraform state backend"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}
