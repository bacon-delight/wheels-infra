variable "name" { type = string }
variable "ui_host" { type = string }
variable "cloudflare_zone_id" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_caller_identity" "current" {}

# Private origin bucket for the built SPA; served only through CloudFront (OAC).
resource "aws_s3_bucket" "ui" {
  bucket = "${var.name}-ui-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket                  = aws_s3_bucket.ui.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "ui" {
  name                              = "${var.name}-ui"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Viewer cert must be in us-east-1 for CloudFront.
resource "aws_acm_certificate" "ui" {
  provider          = aws.us_east_1
  domain_name       = var.ui_host
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "ui_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ui.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.value
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "ui" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.ui.arn
  validation_record_fqdns = [for r in cloudflare_record.ui_cert_validation : r.hostname]
}

resource "aws_cloudfront_distribution" "ui" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.ui_host]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.ui.bucket_regional_domain_name
    origin_id                = "ui-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.ui.id
  }

  default_cache_behavior {
    target_origin_id       = "ui-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    # AWS managed "CachingOptimized" policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    compress        = true
  }

  # SPA routing: client-side routes resolve to index.html.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.ui.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}

# Only this distribution may read the origin bucket (OAC).
resource "aws_s3_bucket_policy" "ui" {
  bucket = aws_s3_bucket.ui.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.ui.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.ui.arn }
      }
    }]
  })
}

resource "cloudflare_record" "ui" {
  zone_id = var.cloudflare_zone_id
  name    = var.ui_host
  type    = "CNAME"
  content = aws_cloudfront_distribution.ui.domain_name
  ttl     = 60
  proxied = false
}

output "ui_bucket" {
  value = aws_s3_bucket.ui.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.ui.id
}

output "ui_url" {
  value = "https://${var.ui_host}"
}
