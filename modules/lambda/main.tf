variable "name" { type = string }
variable "image_uri" { type = string } # ECR image; first apply uses the :bootstrap tag
variable "api_memory_mb" { type = number }
variable "api_provisioned_concurrency" { type = number }

variable "table_name" { type = string }
variable "table_arn" { type = string }
variable "docs_bucket" { type = string }
variable "docs_bucket_arn" { type = string }

variable "ingest_queue_arn" { type = string }
variable "ingest_queue_url" { type = string }
variable "extract_queue_arn" { type = string }
variable "extract_queue_url" { type = string }
variable "textract_topic_arn" { type = string }
variable "event_bus_arn" { type = string }
variable "event_bus_name" { type = string }

variable "cognito_user_pool_arn" { type = string }
variable "cognito_user_pool_id" { type = string }
variable "cognito_client_id" { type = string }

variable "core_region" { type = string }
variable "ses_region" { type = string }
variable "from_email" { type = string }
variable "llm_provider" { type = string }
variable "extract_model" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  env = {
    CORE_REGION          = var.core_region
    SES_REGION           = var.ses_region
    TEXTRACT_REGION      = var.ses_region
    TABLE_NAME           = var.table_name
    DOCS_BUCKET          = var.docs_bucket
    LLM_PROVIDER         = var.llm_provider
    EXTRACT_MODEL        = var.extract_model
    FROM_EMAIL           = var.from_email
    COGNITO_USER_POOL_ID = var.cognito_user_pool_id
    COGNITO_CLIENT_ID    = var.cognito_client_id
    INGEST_QUEUE_URL     = var.ingest_queue_url
    EXTRACT_QUEUE_URL    = var.extract_queue_url
    EVENT_BUS_NAME       = var.event_bus_name
  }
}

# --- Execution role (shared by API + workers) ---
resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name}-lambda"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:${local.account_id}:*"
      },
      {
        Sid    = "Dynamo"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [var.table_arn, "${var.table_arn}/index/*"]
      },
      {
        Sid      = "Docs"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [var.docs_bucket_arn, "${var.docs_bucket_arn}/*"]
      },
      {
        Sid    = "Queues"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [var.ingest_queue_arn, var.extract_queue_arn]
      },
      {
        Sid      = "TextractTopic"
        Effect   = "Allow"
        Action   = ["sns:Publish", "sns:Subscribe"]
        Resource = [var.textract_topic_arn]
      },
      {
        Sid      = "Bedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = ["arn:aws:bedrock:*::foundation-model/*", "arn:aws:bedrock:*:${local.account_id}:inference-profile/*"]
      },
      {
        Sid      = "Textract"
        Effect   = "Allow"
        Action   = ["textract:DetectDocumentText", "textract:AnalyzeDocument", "textract:StartDocumentTextDetection", "textract:GetDocumentTextDetection"]
        Resource = "*"
      },
      {
        Sid      = "SendEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid      = "Events"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = [var.event_bus_arn]
      },
      {
        Sid    = "Cognito"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser", "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminGetUser", "cognito-idp:AdminSetUserPassword",
          "cognito-idp:ListUsers"
        ]
        Resource = [var.cognito_user_pool_arn]
      },
      {
        Sid      = "Secrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:${local.account_id}:secret:wheels/*"
      }
    ]
  })
}

# --- API function (container image) + live alias + provisioned concurrency ---
resource "aws_lambda_function" "api" {
  function_name = "${var.name}-api"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  memory_size   = var.api_memory_mb
  timeout       = 30
  publish       = true
  environment { variables = local.env }
  tags = var.tags

  # Infra seeds the image; middleware CI then owns code via update-function-code.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_alias" "api_live" {
  name             = "live"
  function_name    = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
}

resource "aws_lambda_provisioned_concurrency_config" "api" {
  function_name                     = aws_lambda_function.api.function_name
  qualifier                         = aws_lambda_alias.api_live.name
  provisioned_concurrent_executions = var.api_provisioned_concurrency
}

# --- Workers: same image, different command; latency-tolerant, no provisioned concurrency ---
resource "aws_lambda_function" "worker" {
  for_each      = toset(["parse", "extract", "notify"])
  function_name = "${var.name}-${each.key}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  image_config { command = ["app.pipeline.${each.key}.handler"] }
  memory_size = 1024
  timeout     = 900
  environment { variables = local.env }
  tags = var.tags

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_event_source_mapping" "ingest" {
  event_source_arn = var.ingest_queue_arn
  function_name    = aws_lambda_function.worker["parse"].arn
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "extract" {
  event_source_arn = var.extract_queue_arn
  function_name    = aws_lambda_function.worker["extract"].arn
  batch_size       = 1
}

# Lifecycle transitions -> Notify (SES).
resource "aws_cloudwatch_event_rule" "lifecycle" {
  name           = "${var.name}-lifecycle-notify"
  event_bus_name = var.event_bus_name
  event_pattern  = jsonencode({ source = ["wheels.lifecycle"] })
}

resource "aws_cloudwatch_event_target" "notify" {
  rule           = aws_cloudwatch_event_rule.lifecycle.name
  event_bus_name = var.event_bus_name
  arn            = aws_lambda_function.worker["notify"].arn
}

resource "aws_lambda_permission" "events_notify" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker["notify"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle.arn
}

output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

output "api_alias_arn" {
  value = aws_lambda_alias.api_live.arn
}

# Alias invoke ARN for API Gateway (routes hit the warm `live` alias).
output "api_alias_invoke_arn" {
  value = "arn:aws:apigateway:${var.core_region}:lambda:path/2015-03-31/functions/${aws_lambda_alias.api_live.arn}/invocations"
}
