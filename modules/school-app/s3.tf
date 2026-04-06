# ─── S3 Bucket for Lambda JAR ────────────────────────────────
resource "aws_s3_bucket" "lambda_jar" {
  bucket        = "${var.lambda_jar_bucket}"
  force_destroy = true

  tags = merge(var.tags, { Name = var.lambda_jar_bucket })
}

resource "aws_s3_bucket_versioning" "lambda_jar" {
  bucket = aws_s3_bucket.lambda_jar.id
  versioning_configuration {
    status = "Enabled"
  }
}
