variable "name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Async pipeline transport (no Step Functions in ap-south-2): two work queues, each with a
# dead-letter queue; an SNS topic for Textract async-completion; and an EventBridge bus for
# lifecycle-transition events -> Notify. Long visibility timeout covers a full extraction.

resource "aws_sqs_queue" "ingest_dlq" {
  name = "${var.name}-ingest-dlq"
  tags = var.tags
}

resource "aws_sqs_queue" "ingest" {
  name                       = "${var.name}-ingest"
  visibility_timeout_seconds = 900
  message_retention_seconds  = 1209600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingest_dlq.arn
    maxReceiveCount     = 5
  })
  tags = var.tags
}

resource "aws_sqs_queue" "extract_dlq" {
  name = "${var.name}-extract-dlq"
  tags = var.tags
}

resource "aws_sqs_queue" "extract" {
  name                       = "${var.name}-extract"
  visibility_timeout_seconds = 900
  message_retention_seconds  = 1209600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.extract_dlq.arn
    maxReceiveCount     = 5
  })
  tags = var.tags
}

resource "aws_sns_topic" "textract_complete" {
  name = "${var.name}-textract-complete"
  tags = var.tags
}

resource "aws_cloudwatch_event_bus" "lifecycle" {
  name = "${var.name}-lifecycle"
  tags = var.tags
}

output "ingest_queue_url" {
  value = aws_sqs_queue.ingest.url
}

output "ingest_queue_arn" {
  value = aws_sqs_queue.ingest.arn
}

output "extract_queue_url" {
  value = aws_sqs_queue.extract.url
}

output "extract_queue_arn" {
  value = aws_sqs_queue.extract.arn
}

output "textract_topic_arn" {
  value = aws_sns_topic.textract_complete.arn
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.lifecycle.name
}

output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.lifecycle.arn
}
