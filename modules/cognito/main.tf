variable "name" {
  type = string
}

variable "hosted_ui_domain" {
  type        = string
  description = "Globally-unique Cognito hosted-UI prefix domain"
}

variable "callback_urls" {
  type = list(string)
}

variable "logout_urls" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_region" "current" {}

# One user pool, two groups (provider = Wheels-side incl. finance for now; client). Invites go
# through AdminCreateUser + our own branded SES email, so Cognito's built-in email is unused
# (admin-create-only, no self sign-up).
resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  tags = var.tags
}

# Prefix hosted-UI domain (wheels-dev-<acct>.auth.<region>.amazoncognito.com). A custom domain
# (auth-wheels.logiforma.dev) can be added later — it needs a us-east-1 ACM cert + a DNS record.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.hosted_ui_domain
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_group" "provider" {
  name         = "provider"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Wheels-side users (analyst + finance)"
}

resource "aws_cognito_user_group" "client" {
  name         = "client"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Client-side users (scoped to their engagement)"
}

resource "aws_cognito_user_pool_client" "spa" {
  name            = "${var.name}-spa"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false # public SPA client (PKCE)

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "issuer" {
  value = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "hosted_ui_base_url" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}
