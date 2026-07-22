variable "project" {
  type    = string
  default = "wheels"
}

variable "environment" {
  type    = string
  default = "dev"
}

# --- Regions ---
variable "core_region" {
  type    = string
  default = "ap-south-2" # Hyderabad — all core resources
}

variable "ses_region" {
  type    = string
  default = "ap-south-1" # Mumbai — SES + Textract (not in ap-south-2)
}

# --- DNS / hostnames (Cloudflare-managed zone logiforma.dev) ---
variable "root_domain" {
  type    = string
  default = "logiforma.dev"
}

variable "ui_host" {
  type    = string
  default = "wheels.logiforma.dev"
}

variable "api_host" {
  type    = string
  default = "api-wheels.logiforma.dev"
}

variable "auth_host" {
  type    = string
  default = "auth-wheels.logiforma.dev"
}

variable "from_email" {
  type    = string
  default = "no-reply@logiforma.dev"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone id for logiforma.dev"
  default     = "7ae9d4a4f37b164631c5226b2da92e08"
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Supplied via TF_VAR_cloudflare_api_token (from the CLOUDFLARE_API_TOKEN secret)"
}

# --- Deploy identity (shared GitHub OIDC role already exists; we only reference it) ---
variable "deploy_role_arn" {
  type        = string
  description = "ARN of the existing shared GitHub Actions OIDC deploy role (informational)"
  default     = ""
}

# --- API Lambda (container image) ---
variable "api_lambda_memory_mb" {
  type    = number
  default = 1024
}

variable "api_provisioned_concurrency" {
  type        = number
  default     = 1
  description = "Warm executions on the API `live` alias (1024MB x 1 ~= $10.80/mo)"
}

# --- LLM ---
variable "extract_model" {
  type        = string
  default     = "global.anthropic.claude-sonnet-4-6"
  description = "Bedrock inference-profile id; flip to sonnet-5 when its access is granted"
}

variable "anthropic_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Stored in Secrets Manager for the Anthropic API fallback provider"
}
