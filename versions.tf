terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }

  # Remote state lives in S3 with a DynamoDB lock. Both are created once by ./bootstrap
  # (which uses local state), after which `tofu init` here adopts this backend.
  backend "s3" {
    # Values supplied via -backend-config in CI / `tofu init`:
    #   bucket, key, region, dynamodb_table, encrypt
  }
}
