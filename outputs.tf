# Values the app repos / operators need after apply.

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "api_lambda_function_name" {
  value = module.lambda.api_function_name
}

output "api_endpoint" {
  value = module.apigw.api_endpoint
}

output "ui_url" {
  value = module.cloudfront.ui_url
}

output "ui_bucket" {
  value = module.cloudfront.ui_bucket
}

output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_client_id" {
  value = module.cognito.client_id
}

output "cognito_hosted_ui" {
  value = module.cognito.hosted_ui_base_url
}

output "table_name" {
  value = module.dynamodb.table_name
}

output "docs_bucket" {
  value = module.s3.bucket_name
}
