# ---------------------------------------------------------------------------
# Módulo 2: recursos para el backend remoto (S3 + DynamoDB).
#
# Problema del huevo y la gallina: Terraform necesita que el bucket/tabla ya
# existan para poder usarlos como backend, así que estos recursos se crean
# primero con el backend "local" que ya está en providers.tf. Recién después
# de aplicarlos se actualiza el bloque `backend` en providers.tf y se corre
# `terraform init -migrate-state` para mover el state a S3.
#
# Paso a paso completo en modules/02-backend-remoto.md.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tfstate" {
  # El nombre incluye el account id porque los nombres de bucket S3 son
  # únicos a nivel global, no solo dentro de la cuenta.
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Evita que un `terraform destroy` accidental se lleve puesto el bucket que
  # contiene el state de todo el proyecto. Para destruirlo de verdad hay que
  # sacar este bloque a propósito (ver modules/02-backend-remoto.md).
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tabla usada solo para el locking del state (state locking): evita que dos
# `terraform apply` corran al mismo tiempo y corrompan el state.
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.project_name}-tfstate-lock-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # on-demand: no hay que estimar capacidad para una tabla de locks
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
