terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Empaqueta el código de las Lambdas de action groups (Módulo 3) en .zip
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Backend remoto (Módulo 2): state en S3, locking en DynamoDB. Bootstrap de
  # estos recursos en backend.tf. Detalle del proceso de migración en
  # modules/02-backend-remoto.md.
  backend "s3" {
    bucket         = "agentinfra-tfstate-549884172659"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "agentinfra-tfstate-lock-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
