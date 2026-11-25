terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
  default_tags {
    tags = {
      Project   = "paved-road-platform"
      Ephemeral = "true"
      ManagedBy = "terraform"
      Owner     = "alvieirvansyah"
    }
  }
}

module "network" {
  source = "../../modules/network"
  name   = var.cluster_name
}

module "eks" {
  source             = "../../modules/eks"
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.public_subnet_ids
}

module "ecr" {
  source       = "../../modules/ecr"
  prefix       = var.cluster_name
  repositories = ["portal", "go-http-service", "node-http-service"]
}
