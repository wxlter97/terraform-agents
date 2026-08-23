data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Rol que Bedrock asume para ejecutar el agente e invocar el modelo fundacional
#
# NOTA (Módulo 5): este rol y su policy se prepararon para `aws_bedrockagent_
# agent` (Bedrock Agents "Classic"), pero esa API resultó estar cerrada a
# cuentas sin uso previo del servicio (maintenance mode, ver
# modules/05-bedrock-agent.md) — el Módulo 5 terminó usando AgentCore en su
# lugar, que necesita sus propios roles (`harness_execution_role`,
# `gateway_execution_role` en bedrock-agentcore.tf, con otro trust principal:
# bedrock-agentcore.amazonaws.com, no bedrock.amazonaws.com). Este rol queda
# sin uso por ahora — se deja documentado en vez de borrarlo (IAM no tiene
# costo) por si esta cuenta alguna vez recupera acceso a Bedrock Agents
# Classic, o como referencia de qué hubiera hecho falta.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "bedrock_agent_role" {
  name = "${var.project_name}-bedrock-agent-role-${var.environment}"

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

resource "aws_iam_role_policy" "bedrock_agent_policy" {
  name = "${var.project_name}-bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Resource sin región fija (partición completa) a propósito: el
        # agente (Módulo 5) usa un cross-region inference profile
        # ("us.anthropic..."), que puede enrutar la invocación real a
        # cualquier región de EE.UU. soportada por el profile — no solo
        # var.aws_region. AWS documenta este wildcard como el patrón
        # correcto para IAM + cross-region inference.
        Sid      = "InvokeFoundationModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        # El inference profile en sí (a diferencia del foundation model que
        # referencia) es un recurso de esta cuenta/región, no global — de
        # ahí el ARN con account id. Agregado en el Módulo 5.
        Sid      = "InvokeInferenceProfile"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Rol de ejecución para las Lambdas que serán los "action groups" del agente
# (Módulo 3). Lo dejamos listo desde ya para no reordenar recursos después.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permiso para que Bedrock invoque las Lambdas de action groups
resource "aws_iam_role_policy" "bedrock_invoke_lambda" {
  name = "${var.project_name}-bedrock-invoke-lambda"
  role = aws_iam_role.bedrock_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
    }]
  })
}
