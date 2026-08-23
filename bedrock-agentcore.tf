# ---------------------------------------------------------------------------
# Módulo 5: el agente en sí, sobre Amazon Bedrock AgentCore.
#
# Por qué no es Bedrock Agents Classic (el plan original): `aws_bedrockagent_
# agent` falló al crear con `AccessDeniedException: Bedrock Agents is in
# Maintenance Mode. New agent creation is not available for accounts without
# prior service usage.` AWS cerró Bedrock Agents Classic a cuentas nuevas el
# 30/07/2026 — no es un problema de config, es una puerta cerrada a nivel de
# servicio para esta cuenta. El código que se había escrito para esa versión
# (recursos `aws_bedrockagent_agent*`) nunca llegó a crear nada — ver
# modules/05-bedrock-agent.md para la historia completa.
#
# Arquitectura con AgentCore (todo declarativo, sin escribir código de agente
# propio — a diferencia de un `agent_runtime` con contenedor custom):
#   - `aws_bedrockagentcore_harness`: el agente — instrucciones, modelo, y
#     qué tools puede usar. Es el sucesor más cercano a `aws_bedrockagent_
#     agent`, y el que efectivamente actúa como "harness" en el sentido de
#     modules/agent-harness.md.
#   - `aws_bedrockagentcore_gateway` + `..._gateway_target`: AgentCore no
#     tiene "action groups" ni asociación directa a una Knowledge Base como
#     Bedrock Agents Classic — todo tool (incluida la KB) se expone a través
#     de un Gateway que traduce llamadas MCP a invocaciones de Lambda. De ahí
#     la Lambda nueva `query_faqs` (puente hacia la Knowledge Base del
#     Módulo 4) y por qué create_ticket/get_ticket_status (Módulo 3) tuvieron
#     que reescribirse: el evento/respuesta que le pasa un Gateway target a
#     una Lambda es distinto al de un action group de Bedrock Agents Classic.
# ---------------------------------------------------------------------------

locals {
  # Claude Haiku 4.5: el modelo "económico" que el README pide para mantener
  # el costo en centavos. Solo está disponible como INFERENCE_PROFILE en esta
  # cuenta/región (no como on-demand directo) — de ahí el Resource con
  # wildcard de región en la policy de más abajo: un cross-region inference
  # profile puede enrutar la invocación real a cualquier región de EE.UU.
  # soportada por el profile, no solo var.aws_region. Verificado con
  # `aws bedrock list-inference-profiles`.
  agent_foundation_model = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

# ---------------------------------------------------------------------------
# Lambda puente hacia la Knowledge Base — no existía en el Módulo 3. AgentCore
# no tiene un tipo de tool nativo para "Knowledge Base", así que se expone
# igual que las otras dos: como target de Gateway sobre una Lambda.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_kb_retrieve" {
  name = "${var.project_name}-lambda-kb-retrieve"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:Retrieve"]
      Resource = aws_bedrockagent_knowledge_base.helpdesk.arn
    }]
  })
}

data "archive_file" "query_faqs" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/query_faqs"
  output_path = "${path.module}/lambda/query_faqs.zip"
}

resource "aws_lambda_function" "query_faqs" {
  function_name = "${var.project_name}-query-faqs-${var.environment}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.query_faqs.output_path
  source_code_hash = data.archive_file.query_faqs.output_base64sha256

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.helpdesk.id
    }
  }
}

# ---------------------------------------------------------------------------
# Gateway — expone las tres Lambdas (create_ticket, get_ticket_status,
# query_faqs) como tools MCP que el harness puede llamar.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "gateway_execution_role" {
  name = "${var.project_name}-gateway-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

# El Gateway invoca las Lambdas con sus propias credenciales (identity-based,
# acá) — el permiso resource-based del otro lado (que el Gateway pueda
# invocar cada Lambda puntual) son los aws_lambda_permission de más abajo.
resource "aws_iam_role_policy" "gateway_invoke_lambdas" {
  name = "${var.project_name}-gateway-invoke-lambdas"
  role = aws_iam_role.gateway_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.create_ticket.arn,
        aws_lambda_function.get_ticket_status.arn,
        aws_lambda_function.query_faqs.arn,
      ]
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "helpdesk" {
  name            = "${var.project_name}-helpdesk-gateway-${var.environment}"
  role_arn        = aws_iam_role.gateway_execution_role.arn
  authorizer_type = "AWS_IAM" # SigV4 — mismo patrón de auth que el resto del proyecto, sin Cognito/JWT
  protocol_type   = "MCP"
}

resource "aws_bedrockagentcore_gateway_target" "create_ticket" {
  gateway_identifier = aws_bedrockagentcore_gateway.helpdesk.gateway_id
  name               = "create-ticket"
  description        = "Crea un ticket de soporte cuando la Knowledge Base no tiene la respuesta a la consulta del usuario."

  credential_provider_configuration {
    gateway_iam_role {} # el Gateway usa su propio rol (arriba) para invocar la Lambda
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.create_ticket.arn

        tool_schema {
          inline_payload {
            name        = "create_ticket"
            description = "Crea un nuevo ticket de soporte con la descripción del problema del usuario."

            input_schema {
              type = "object"

              property {
                name        = "description"
                type        = "string"
                required    = true
                description = "Descripción clara del problema reportado por el usuario."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "get_ticket_status" {
  gateway_identifier = aws_bedrockagentcore_gateway.helpdesk.gateway_id
  name               = "get-ticket-status"
  description        = "Consulta el estado actual (open, in_progress, closed) de un ticket de soporte existente dado su ID."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.get_ticket_status.arn

        tool_schema {
          inline_payload {
            name        = "get_ticket_status"
            description = "Devuelve el estado actual de un ticket dado su ticket_id."

            input_schema {
              type = "object"

              property {
                name        = "ticket_id"
                type        = "string"
                required    = true
                description = "El identificador único (ticket_id) del ticket a consultar."
              }
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "query_faqs" {
  gateway_identifier = aws_bedrockagentcore_gateway.helpdesk.gateway_id
  name               = "query-faqs"
  description        = "Busca en la base de conocimiento de FAQs de soporte técnico (reseteo de contraseña, cómo se crean y consultan tickets)."

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.query_faqs.arn

        tool_schema {
          inline_payload {
            name        = "query_faqs"
            description = "Busca en las FAQs de soporte técnico usando la consulta del usuario en lenguaje natural."

            input_schema {
              type = "object"

              property {
                name        = "query"
                type        = "string"
                required    = true
                description = "La pregunta o consulta del usuario, en lenguaje natural."
              }
            }
          }
        }
      }
    }
  }
}

# Permiso resource-based: el Gateway (no el harness) es quien efectivamente
# invoca cada Lambda, así que source_arn es el ARN del Gateway.
resource "aws_lambda_permission" "gateway_invoke_create_ticket" {
  statement_id  = "AllowAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_ticket.function_name
  principal     = "bedrock-agentcore.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.helpdesk.gateway_arn
}

resource "aws_lambda_permission" "gateway_invoke_get_ticket_status" {
  statement_id  = "AllowAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_ticket_status.function_name
  principal     = "bedrock-agentcore.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.helpdesk.gateway_arn
}

resource "aws_lambda_permission" "gateway_invoke_query_faqs" {
  statement_id  = "AllowAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_faqs.function_name
  principal     = "bedrock-agentcore.amazonaws.com"
  source_arn    = aws_bedrockagentcore_gateway.helpdesk.gateway_arn
}

# ---------------------------------------------------------------------------
# Harness — el agente. Rol de ejecución propio (trust bedrock-agentcore.
# amazonaws.com, distinto de bedrock_agent_role del Módulo 1 — ver la nota en
# iam.tf). La policy de acá es la baseline que documenta AWS para cualquier
# harness (modelo, logs, X-Ray, ECR Public para el runtime administrado) más
# el permiso puntual para invocar nuestro Gateway.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "harness_execution_role" {
  name = "${var.project_name}-harness-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "harness_execution_policy" {
  name = "${var.project_name}-harness-execution-policy"
  role = aws_iam_role.harness_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockModelInvocation"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = ["arn:aws:bedrock:*::foundation-model/*", "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
      },
      {
        # El runtime administrado del harness se descarga de ECR Public en
        # cada sesión — no es un container propio, así que hace falta este
        # permiso aunque no gestionemos ninguna imagen nosotros.
        Sid      = "EcrPublicTokenAccess"
        Effect   = "Allow"
        Action   = ["ecr-public:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "StsForEcrPublicPull"
        Effect   = "Allow"
        Action   = ["sts:GetServiceBearerToken"]
        Resource = "*"
      },
      {
        Sid      = "XRayTracingAccess"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchLogsGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogStreams"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"
      },
      {
        Sid      = "CloudWatchLogsDescribeGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Sid      = "CloudWatchLogsStream"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
      },
      {
        Sid      = "CloudWatchLogsPutResourcePolicy"
        Effect   = "Allow"
        Action   = ["logs:PutResourcePolicy"]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchMetricsPublish"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" }
        }
      },
      {
        Sid    = "AgentCoreWorkloadIdentity"
        Effect = "Allow"
        Action = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT"]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/harness_${var.project_name}helpdesk${var.environment}-*",
        ]
      },
      {
        # Permiso puntual para que el harness llame a nuestro Gateway (tool
        # type "agentcore_gateway" más abajo) — no forma parte de la baseline
        # que documenta AWS, se agrega porque este harness lo necesita.
        Sid      = "AgentCoreGatewayAccess"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeGateway"]
        Resource = aws_bedrockagentcore_gateway.helpdesk.gateway_arn
      },
      {
        # Sí forma parte de la baseline (a diferencia de lo que se asumió al
        # escribir esto la primera vez): el harness aprovisiona una memoria
        # por default automáticamente (historial de conversación por
        # sesión) aunque no se configure el bloque `memory` explícitamente —
        # sin este permiso, InvokeHarness falla con AccessDeniedException en
        # ListEvents. Descubierto probando una invocación real, no leyendo
        # docs — ver modules/06-api-gateway.md.
        #
        # El patrón de ARN que documenta AWS es
        # "memory/harness_<agentNameAbbrv>_*", pero el recurso real que creó
        # esta cuenta no tiene el prefijo "harness_" (ver el módulo doc) — se
        # usa wildcard completo del tipo de recurso en vez de adivinar el
        # patrón exacto.
        Sid      = "AgentCoreMemory"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:DeleteEvent", "bedrock-agentcore:GetEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:RetrieveMemoryRecords"]
        Resource = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:memory/*"
      }
    ]
  })
}

resource "aws_bedrockagentcore_harness" "helpdesk" {
  # Sin guiones a propósito: harness_name solo acepta [a-zA-Z][a-zA-Z0-9_]{0,39}
  # (a diferencia del resto de los nombres del proyecto, que sí usan guiones).
  harness_name       = "${var.project_name}helpdesk${var.environment}"
  execution_role_arn = aws_iam_role.harness_execution_role.arn

  model {
    bedrock_model_config {
      model_id = local.agent_foundation_model
    }
  }

  system_prompt {
    text = <<-EOT
      Sos un asistente de soporte técnico (helpdesk). Ayudás a los usuarios
      siguiendo estos pasos, en orden:

      1. Primero, usá la tool query_faqs para buscar la respuesta en la base
         de conocimiento. Si encontrás información que responde la pregunta
         del usuario, respondé basándote en esa información y no crees un
         ticket.
      2. Si la base de conocimiento no tiene la respuesta y el usuario tiene
         un problema que requiere seguimiento, creá un ticket de soporte con
         la tool create_ticket, usando una descripción clara del problema.
      3. Si el usuario pregunta por el estado de un ticket que ya existe, usá
         get_ticket_status con el ticket_id que te dé. Si no te dio un
         ticket_id, pedíselo antes de llamar a la tool.
      4. Sé conciso. No inventes información que no esté en el resultado de
         una tool.
    EOT
  }

  tool {
    name = "helpdesk_tools"
    type = "agentcore_gateway"

    config {
      agentcore_gateway {
        gateway_arn = aws_bedrockagentcore_gateway.helpdesk.gateway_arn

        outbound_auth {
          aws_iam = true # SigV4 con el rol de ejecución del harness, mismo patrón que el authorizer_type del Gateway
        }
      }
    }
  }

  depends_on = [
    aws_bedrockagentcore_gateway_target.create_ticket,
    aws_bedrockagentcore_gateway_target.get_ticket_status,
    aws_bedrockagentcore_gateway_target.query_faqs,
  ]
}
