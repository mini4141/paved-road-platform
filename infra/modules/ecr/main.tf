terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = "${var.prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # cost guardrail: repos are destroyable even with images

  image_scanning_configuration {
    scan_on_push = true
  }
}
