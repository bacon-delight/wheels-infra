# One-time bootstrap: creates the S3 bucket + DynamoDB table that back the main config's
# remote state. Runs with LOCAL state (no backend). Run once, then `tofu init` the root
# config against this bucket.
#
#   cd bootstrap && tofu init && tofu apply
#
# It deliberately does NOT create the GitHub OIDC provider or deploy role — those already
# exist in this account (shared across projects). Add the wheels-* repo subjects to that
# role's trust policy manually (see repo README).

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.core_region
  default_tags {
    tags = {
      Project   = "wheels"
      ManagedBy = "opentofu-bootstrap"
    }
  }
}

variable "core_region" {
  type    = string
  default = "ap-south-2"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = "wheels-tfstate-${data.aws_caller_identity.current.account_id}-aps2"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "wheels-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.lock.name
}

output "backend_init_hint" {
  value = <<-EOT
    tofu init \
      -backend-config="bucket=${aws_s3_bucket.state.id}" \
      -backend-config="key=wheels/dev/terraform.tfstate" \
      -backend-config="region=${var.core_region}" \
      -backend-config="dynamodb_table=${aws_dynamodb_table.lock.name}" \
      -backend-config="encrypt=true"
  EOT
}
