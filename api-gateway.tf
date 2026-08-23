# ---------------------------------------------------------------------------
# Módulo 6: API Gateway (HTTP API) + Lambda proxy — expone el harness del
# Módulo 5 como un endpoint HTTP al que cualquier front-end o script puede
# llamar (ver "Caso de uso" en README.md).
#
# El AWS CLI todavía no tiene un comando `invoke-harness` (ver
# modules/05-bedrock-agent.md), pero el boto3 que trae el runtime administrado
# de Lambda (python3.12) sí soporta `invoke_harness` — se verificó desplegando
# una Lambda de diagnóstico antes de escribir este módulo (boto3 1.42.97),
# así que el proxy se pudo escribir directo sin rodeos.
#
# Nota de seguridad: el endpoint queda sin autenticación (`authorization_type`
# por default = "NONE") a propósito, para que "cualquier script" pueda
# llamarlo tal como describe el caso de uso — pero eso significa que cualquiera
# con la URL puede generar invocaciones de Bedrock (con costo) sin límite.
# Para un uso real (no de aprendizaje) esto necesitaría como mínimo un
# throttle de uso y probablemente auth (IAM o un authorizer JWT).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "api_proxy_role" {
  name = "${var.project_name}-api-proxy-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_proxy_basic" {
  role       = aws_iam_role.api_proxy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Tabla de permisos de InvokeHarness (ver modules/05-bedrock-agent.md): hacen
# falta las dos acciones, sobre el ARN del harness.
resource "aws_iam_role_policy" "api_proxy_invoke_harness" {
  name = "${var.project_name}-api-proxy-invoke-harness"
  role = aws_iam_role.api_proxy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:InvokeHarness", "bedrock-agentcore:InvokeAgentRuntime"]
      Resource = aws_bedrockagentcore_harness.helpdesk.arn
    }]
  })
}

data "archive_file" "chat_proxy" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/chat_proxy"
  output_path = "${path.module}/lambda/chat_proxy.zip"
}

resource "aws_lambda_function" "chat_proxy" {
  function_name = "${var.project_name}-chat-proxy-${var.environment}"
  role          = aws_iam_role.api_proxy_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  # El default de 3s no alcanza: invoke_harness puede implicar varias vueltas
  # de tool-calling (Gateway -> Lambda) antes de la respuesta final.
  timeout = 30

  filename         = data.archive_file.chat_proxy.output_path
  source_code_hash = data.archive_file.chat_proxy.output_base64sha256

  environment {
    variables = {
      HARNESS_ARN = aws_bedrockagentcore_harness.helpdesk.arn
    }
  }
}

resource "aws_apigatewayv2_api" "helpdesk" {
  name          = "${var.project_name}-helpdesk-api-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.helpdesk.id
  # "$default" es un nombre especial de API Gateway: la ruta queda en la raíz
  # del endpoint (sin prefijo de stage en la URL), no un literal a elegir.
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "chat_proxy" {
  api_id                 = aws_apigatewayv2_api.helpdesk.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST" # método interno con el que API Gateway invoca la Lambda, no el método HTTP público
  integration_uri        = aws_lambda_function.chat_proxy.invoke_arn
  payload_format_version = "2.0" # shape simplificado de evento/respuesta que usa index.py
}

resource "aws_apigatewayv2_route" "chat" {
  api_id    = aws_apigatewayv2_api.helpdesk.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.chat_proxy.id}"
}

resource "aws_lambda_permission" "apigw_invoke_chat_proxy" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.helpdesk.execution_arn}/*/*"
}
