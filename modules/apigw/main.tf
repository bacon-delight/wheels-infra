variable "name" { type = string }
variable "api_host" { type = string }
variable "ui_host" { type = string }
variable "cognito_issuer" { type = string }
variable "cognito_client_id" { type = string }
variable "lambda_alias_arn" { type = string }     # integration target (warm `live` alias)
variable "lambda_function_name" { type = string } # for the invoke permission
variable "cloudflare_zone_id" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

# HTTP API (cheaper + native JWT authorizer). Default route is JWT-protected; /health is public.
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = ["https://${var.ui_host}", "http://localhost:5173", "http://localhost:3000"]
    allow_methods     = ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"]
    allow_headers     = ["authorization", "content-type"]
    allow_credentials = true
    max_age           = 3600
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_alias_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name}-cognito"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = var.cognito_issuer
  }
}

resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "health" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  qualifier     = "live"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# --- Custom domain: cert (ap-south-2) validated via Cloudflare DNS ---
resource "aws_acm_certificate" "api" {
  domain_name       = var.api_host
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in cloudflare_record.api_cert_validation : r.hostname]
}

resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = var.api_host
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.http.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_host
  type    = "CNAME"
  content = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
  ttl     = 60
  proxied = false
}

output "api_endpoint" {
  value = "https://${var.api_host}"
}

output "api_default_endpoint" {
  value = aws_apigatewayv2_api.http.api_endpoint
}
