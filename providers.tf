# Core resources in ap-south-2 (Hyderabad). Two aliased providers:
#   - us_east_1: CloudFront requires its ACM cert in us-east-1.
#   - ses:       SES + Textract are not in ap-south-2; they live in ap-south-1.

provider "aws" {
  region = var.core_region
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "ses"
  region = var.ses_region
  default_tags {
    tags = local.tags
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
