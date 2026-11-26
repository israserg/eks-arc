# Long-lived foundations: things that must survive a rebuild of the cluster.
# Apply this stack BEFORE the cluster stack in the parent directory. Rarely destroy it.

variable "region" {
  description = "AWS region for the project (must match the project's selected Region)."
  type        = string
  default     = "eu-north-1"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "eks-arc-training"
      ManagedBy = "terraform"
    }
  }
}

# Container image repository for the demo app.
resource "aws_ecr_repository" "demo" {
  name = "eks-arc-demo"

  # Immutable tags: once 1.0.42-abc1234 is pushed it can't be overwritten.
  image_tag_mutability = "IMMUTABLE"

  # Deliberately false: destroying this stack fails while images exist, instead of silently
  # deleting them (the cluster stack used true, which is why images vanished with the cluster).
  force_delete = false

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Helm chart repository. "helm push oci://<registry>/charts" with a chart named "demo"
# lands in "charts/demo".
resource "aws_ecr_repository" "demo_chart" {
  name                 = "charts/demo"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
}

# Without a limit, every build adds an image forever. Keep the newest 30 per repository.
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each = {
    demo       = aws_ecr_repository.demo.name
    demo_chart = aws_ecr_repository.demo_chart.name
  }

  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

output "demo_repository_url" {
  value = aws_ecr_repository.demo.repository_url
}

output "demo_chart_repository_url" {
  value = aws_ecr_repository.demo_chart.repository_url
}
