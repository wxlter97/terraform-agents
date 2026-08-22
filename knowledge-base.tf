# ---------------------------------------------------------------------------
# Módulo 4: Knowledge Base (RAG) — FAQs en S3 + vector store en S3 Vectors.
#
# Historia real de cómo se llegó a esto (dejamos el rastro a propósito, ver
# modules/04-knowledge-base.md para el detalle completo): el plan original
# era Aurora Serverless v2 + pgvector vía RDS Data API. Esta cuenta de AWS es
# de tipo "Free Plan", que obliga a crear clusters Aurora con "Express
# Configuration" — y los clusters Express no pueden habilitar la Data API
# (no tienen networking de VPC, que la Data API necesita). Dead end
# confirmado a mano contra la cuenta real, no en teoría. S3 Vectors lo
# resuelve mejor igual: sin cluster, sin VPC, sin credenciales de DB — es
# almacenamiento de vectores nativo de S3, facturado por uso.
#
# Costo (a diferencia de los módulos 1-3, este SÍ puede generar costo, pero
# mucho más acotado que la Aurora original — ver modules/04-knowledge-base.md
# para el detalle):
#   - S3 Vectors: sin cluster corriendo, se paga por almacenamiento + por
#     request de query/ingesta. Para el puñado de FAQs de este proyecto,
#     centavos de dólar en el peor caso.
#   - El bucket S3 de FAQs (contenido fuente, no vectores) son centavos.
#   - Bedrock cobra por token al generar embeddings en la ingesta — para este
#     volumen, centavos de dólar.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Bucket S3 con el contenido de FAQ (la fuente de datos que Bedrock ingesta)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "faqs" {
  bucket = "${var.project_name}-faqs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "faqs" {
  bucket = aws_s3_bucket.faqs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "faqs" {
  bucket = aws_s3_bucket.faqs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sube cada archivo de knowledge-base/faqs/ tal cual — agregar un .md nuevo ahí
# alcanza para que el próximo `apply` lo suba (la ingesta a Bedrock sigue
# siendo un paso manual, ver modules/04-knowledge-base.md).
resource "aws_s3_object" "faqs" {
  for_each = fileset("${path.module}/knowledge-base/faqs", "*.md")

  bucket       = aws_s3_bucket.faqs.id
  key          = each.value
  source       = "${path.module}/knowledge-base/faqs/${each.value}"
  etag         = filemd5("${path.module}/knowledge-base/faqs/${each.value}")
  content_type = "text/markdown"
}

# ---------------------------------------------------------------------------
# S3 Vectors — el vector store. Un "vector bucket" (distinto de un bucket S3
# normal, es un recurso propio del servicio S3 Vectors) con un solo índice
# adentro. Sin VPC, sin cluster, sin credenciales de base de datos: Bedrock
# accede vía IAM directamente (mismo patrón que S3/DynamoDB), no vía Data API.
# ---------------------------------------------------------------------------
resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "${var.project_name}-kb-vectors-${var.environment}"

  encryption_configuration {
    sse_type = "AES256"
  }
}

resource "aws_s3vectors_index" "kb" {
  index_name         = "helpdesk-faqs"
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  data_type          = "float32"
  dimension          = 1024 # tiene que matchear la dimensión del modelo de embeddings (Titan v2 = 1024)
  distance_metric    = "cosine"
}

# ---------------------------------------------------------------------------
# Rol IAM que asume el servicio de Knowledge Bases de Bedrock — distinto de
# `bedrock_agent_role` (Módulo 1), que es el rol del agente en sí.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "bedrock_kb_role" {
  name = "${var.project_name}-bedrock-kb-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_policy" {
  name = "${var.project_name}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeEmbeddingModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${local.embedding_model_id}"
      },
      {
        Sid      = "ReadFaqBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.faqs.arn}/*"
      },
      {
        Sid      = "ListFaqBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.faqs.arn
      },
      {
        # Lista exacta que documenta AWS para el rol de servicio de una KB
        # respaldada por S3 Vectors — ver modules/04-knowledge-base.md.
        Sid      = "S3VectorBucketReadAndWritePermission"
        Effect   = "Allow"
        Action   = ["s3vectors:PutVectors", "s3vectors:GetVectors", "s3vectors:DeleteVectors", "s3vectors:QueryVectors", "s3vectors:GetIndex"]
        Resource = aws_s3vectors_index.kb.index_arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# La Knowledge Base y su data source
# ---------------------------------------------------------------------------
locals {
  # Titan Embeddings v2 con 1024 dimensiones — usado tanto acá como en
  # aws_s3vectors_index.kb.dimension, tienen que coincidir.
  embedding_model_id = "amazon.titan-embed-text-v2:0"
}

resource "aws_bedrockagent_knowledge_base" "helpdesk" {
  name     = "${var.project_name}-helpdesk-kb-${var.environment}"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${local.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb.index_arn
    }
  }
}

resource "aws_bedrockagent_data_source" "faqs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.helpdesk.id
  name              = "${var.project_name}-faqs-${var.environment}"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.faqs.arn
    }
  }

  # No hay recurso de Terraform para disparar la ingesta (StartIngestionJob) —
  # se corre manualmente después del apply, ver modules/04-knowledge-base.md.
}
