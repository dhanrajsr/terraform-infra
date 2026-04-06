output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = "https://${aws_cloudfront_distribution.ui.domain_name}"
}

output "s3_bucket" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.ui.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.ui.id
}
