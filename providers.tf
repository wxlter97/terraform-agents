terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.24 requerido por los recursos aws_s3vectors_* (Módulo 4, vector
      # store del Knowledge Base) — subido desde "~> 5.0" para eso. El único
      # cambio de la guía de migración v5→v6 que toca este repo es el rename
      # de `region` a `bucket_region` en aws_s3_bucket (no lo usábamos en
      # ningún .tf/output), así que la subida fue de bajo riesgo.
      version = "~> 6.0"
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
