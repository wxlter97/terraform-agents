# ---------------------------------------------------------------------------
# Módulo 7: observabilidad — log groups con retención acotada, alarms básicas
# (errores/throttles de Lambda, 5xx/latencia de API Gateway) y un budget de
# AWS para cubrir el hueco que quedó documentado en el Módulo 6: el endpoint
# público POST /chat no tiene auth ni throttle, así que un budget es la única
# red de seguridad contra gasto descontrolado que este proyecto tiene hasta
# acá.
#
# Los cuatro Lambdas (create_ticket, get_ticket_status, query_faqs,
# chat_proxy) y el runtime del harness ya habían generado sus log groups solo
# con invocarlos (retención "never expire" por default) — tres de los cuatro
# de Lambda y el del harness se importaron a este state en vez de recrearlos
# (`terraform import`, ver modules/07-observabilidad.md); get_ticket_status
# no tenía uno todavía porque nunca se había invocado directo.
# ---------------------------------------------------------------------------

locals {
  # name = nombre real del log group (ya existente o a crear), arn = para el
  # dashboard de alarms de abajo (dimensions usan el nombre de función, no
  # el del log group).
  tool_lambdas = {
    create_ticket     = aws_lambda_function.create_ticket.function_name
    get_ticket_status = aws_lambda_function.get_ticket_status.function_name
    query_faqs        = aws_lambda_function.query_faqs.function_name
    chat_proxy        = aws_lambda_function.chat_proxy.function_name
  }
}

# ---------------------------------------------------------------------------
# Log groups — retención de 14 días en vez del default "never expire" de
# Lambda, para no acumular logs (y costo de storage) indefinidamente en un
# proyecto que se prende y apaga con frecuencia.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.tool_lambdas

  name              = "/aws/lambda/${each.value}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "harness_runtime" {
  name              = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_harness.helpdesk.environment_actual[0].agentcore_runtime_environment[0].agent_runtime_id}-DEFAULT"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# SNS: destino de todas las alarms de este módulo.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${var.environment}"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "wxlter.97@gmail.com"
  # AWS manda un mail de confirmación de la suscripción — hay que clickearlo
  # una vez para que las notificaciones empiecen a llegar de verdad.
}

# ---------------------------------------------------------------------------
# Alarms de Lambda: errores y throttles, una de cada una por función.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.tool_lambdas

  alarm_name          = "${var.project_name}-${each.key}-errors-${var.environment}"
  alarm_description   = "Errores de la Lambda ${each.value} en los últimos 5 minutos"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = local.tool_lambdas

  alarm_name          = "${var.project_name}-${each.key}-throttles-${var.environment}"
  alarm_description   = "Throttles de la Lambda ${each.value} en los últimos 5 minutos"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Alarms de API Gateway: 5xx (fallas reales del proxy/harness) y latencia
# (proxy de "latencia del agente" — ver nota abajo sobre por qué no se usa
# directamente la métrica gen_ai.client.operation.duration del harness).
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-api-5xx-${var.environment}"
  alarm_description   = "Errores 5xx en el endpoint /chat en los últimos 5 minutos"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.helpdesk.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.project_name}-api-latency-${var.environment}"
  alarm_description   = "Latencia p90 del endpoint /chat > 25s en los últimos 5 minutos (invoke_harness puede implicar varias vueltas de tool-calling)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = aws_apigatewayv2_api.helpdesk.id }
  extended_statistic  = "p90"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 25000 # ms — el timeout de chat_proxy es 30s (api-gateway.tf), este alarm avisa antes de llegar ahí
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# Budget: la única red de seguridad contra gasto descontrolado del endpoint
# público sin auth (Módulo 6). Filtrado por el tag Project que default_tags
# ya pone en todo recurso — cubre Bedrock, Lambda, API Gateway, S3 Vectors,
# todo lo que este proyecto pueda generar de costo.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget-${var.environment}"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project_name)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["wxlter.97@gmail.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["wxlter.97@gmail.com"]
  }
}
