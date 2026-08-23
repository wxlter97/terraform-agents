# ---------------------------------------------------------------------------
# Módulo 8: CI/CD — GitHub Actions corre terraform fmt/validate/plan en cada
# PR (comentando el plan) y terraform apply solo manual (workflow_dispatch,
# nunca automático al mergear a master). Los workflows en sí viven en
# .github/workflows/ (YAML, no Terraform) — este archivo es la parte de
# infraestructura real que necesitan: un rol IAM que GitHub Actions puede
# asumir vía OIDC, sin guardar credenciales de AWS como secret de GitHub.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list quedó opcional en el provider de AWS: ya no hace falta
  # calcularlo a mano, AWS valida el certificado de GitHub contra su propio
  # bundle de CAs confiables en vez de depender de un thumbprint fijo.
}

resource "aws_iam_role" "github_actions_ci" {
  name = "${var.project_name}-github-actions-ci-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Restringido a este repo puntual (cualquier branch/PR/workflow
        # dentro de él) — no a toda la org ni a cualquier repo de GitHub.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:wxlter97/terraform-agents:*"
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Permisos amplios a propósito, no least-privilege — ver
# modules/08-cicd.md para el porqué (11 servicios de AWS distintos entre
# todos los módulos, escribir una policy realmente acotada para cada uno es
# un proyecto en sí mismo, fuera de alcance para un proyecto de
# aprendizaje). Documentado como simplificación conocida, no un descuido.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "github_actions_ci_policy" {
  name = "${var.project_name}-github-actions-ci-policy"
  role = aws_iam_role.github_actions_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:*",
        "s3:*",
        "s3vectors:*",
        "dynamodb:*",
        "lambda:*",
        "bedrock:*",
        "bedrock-agentcore:*",
        "apigateway:*",
        "logs:*",
        "cloudwatch:*",
        "sns:*",
        "budgets:*",
        "sts:GetCallerIdentity",
      ]
      Resource = "*"
    }]
  })
}
