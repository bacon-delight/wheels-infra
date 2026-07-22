# Root wiring. Modules are added incrementally; each is self-contained under ./modules.
# Order of build: ecr -> dynamodb -> s3 -> cognito -> sqs-pipeline -> lambda(api+workers)
# -> apigw -> cloudfront -> cloudflare-dns -> ses-notify.

data "aws_caller_identity" "current" {}

data "aws_region" "core" {}

# ECR repo for the middleware container image (name matches wheels-middleware CI's ECR_REPO).
module "ecr" {
  source = "./modules/ecr"
  name   = "wheels-middleware"
  tags   = local.tags
}

# The repo is created out-of-band first (so the middleware image can be pushed before the
# Lambda exists); Tofu adopts it instead of trying to recreate it.
import {
  to = module.ecr.aws_ecr_repository.this
  id = "wheels-middleware"
}

module "dynamodb" {
  source = "./modules/dynamodb"
  name   = local.name_prefix
  tags   = local.tags
}

module "s3" {
  source       = "./modules/s3"
  name         = "${local.name_prefix}-docs-${data.aws_caller_identity.current.account_id}"
  cors_origins = ["https://${var.ui_host}", "http://localhost:5173", "http://localhost:3000"]
  tags         = local.tags
}

module "cognito" {
  source           = "./modules/cognito"
  name             = local.name_prefix
  hosted_ui_domain = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
  callback_urls    = ["https://${var.ui_host}/callback", "http://localhost:5173/callback"]
  logout_urls      = ["https://${var.ui_host}/", "http://localhost:5173/"]
  tags             = local.tags
}

module "pipeline" {
  source = "./modules/sqs-pipeline"
  name   = local.name_prefix
  tags   = local.tags
}
module "lambda" {
  source                      = "./modules/lambda"
  name                        = local.name_prefix
  image_uri                   = "${module.ecr.repository_url}:latest"
  api_memory_mb               = var.api_lambda_memory_mb
  api_provisioned_concurrency = var.api_provisioned_concurrency

  table_name      = module.dynamodb.table_name
  table_arn       = module.dynamodb.table_arn
  docs_bucket     = module.s3.bucket_name
  docs_bucket_arn = module.s3.bucket_arn

  ingest_queue_arn   = module.pipeline.ingest_queue_arn
  ingest_queue_url   = module.pipeline.ingest_queue_url
  extract_queue_arn  = module.pipeline.extract_queue_arn
  extract_queue_url  = module.pipeline.extract_queue_url
  textract_topic_arn = module.pipeline.textract_topic_arn
  event_bus_arn      = module.pipeline.event_bus_arn
  event_bus_name     = module.pipeline.event_bus_name

  cognito_user_pool_arn = module.cognito.user_pool_arn
  cognito_user_pool_id  = module.cognito.user_pool_id
  cognito_client_id     = module.cognito.client_id

  core_region   = var.core_region
  ses_region    = var.ses_region
  from_email    = var.from_email
  llm_provider  = "fallback"
  extract_model = var.extract_model
  tags          = local.tags
}

module "apigw" {
  source               = "./modules/apigw"
  name                 = local.name_prefix
  api_host             = var.api_host
  ui_host              = var.ui_host
  cognito_issuer       = module.cognito.issuer
  cognito_client_id    = module.cognito.client_id
  lambda_alias_arn     = module.lambda.api_alias_arn
  lambda_function_name = module.lambda.api_function_name
  cloudflare_zone_id   = var.cloudflare_zone_id
  tags                 = local.tags
}

module "cloudfront" {
  source             = "./modules/cloudfront"
  name               = local.name_prefix
  ui_host            = var.ui_host
  cloudflare_zone_id = var.cloudflare_zone_id
  tags               = local.tags
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    cloudflare    = cloudflare
  }
}

# SES is already provisioned in ap-south-1 (verified logiforma.dev); the Lambda role has
# ses:SendEmail. No SES resources are managed here — the Notify Lambda sends cross-region.
