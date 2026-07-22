variable "name" {
  type = string
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins allowed to presign-upload (the UI host + localhost dev)"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Documents bucket: source PDFs + document versions, page-render PNGs, OCR JSON, billing
# configs, invoice CSVs. Private; browser uploads go through presigned PUTs (hence CORS).
resource "aws_s3_bucket" "docs" {
  bucket = var.name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "docs" {
  bucket = aws_s3_bucket.docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    # SSE-S3 (AES256): encrypted at rest with no KMS key-policy grants needed on the Lambda
    # role. Swap to aws:kms + a CMD if a customer-managed key is required later.
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  cors_rule {
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = var.cors_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

output "bucket_name" {
  value = aws_s3_bucket.docs.id
}

output "bucket_arn" {
  value = aws_s3_bucket.docs.arn
}
