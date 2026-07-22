variable "name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ECR repo for the middleware container image. wheels-middleware CI pushes tags here;
# the Lambda is created from an image in this repo. Mutable tags so `:GITHUB_SHA` +
# update-function-code work without recreating the repo.
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# Keep only recent images to control storage cost.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}

output "name" {
  value = aws_ecr_repository.this.name
}
