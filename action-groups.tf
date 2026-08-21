# ---------------------------------------------------------------------------
# Módulo 3: action groups del agente — Lambdas `create_ticket` y
# `get_ticket_status` sobre una tabla DynamoDB de tickets (ver "Caso de uso"
# en README.md). `aws_iam_role.lambda_exec_role` ya existía desde el Módulo 1.
#
# El permiso resource-based para que Bedrock invoque estas Lambdas
# (aws_lambda_permission con source_arn del Agent Alias) se agrega recién en
# el Módulo 5, cuando el alias exista y tengamos su ARN. Por ahora quedan
# desplegadas pero nada externo puede invocarlas todavía.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "tickets" {
  name         = "${var.project_name}-tickets-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticket_id"

  attribute {
    name = "ticket_id"
    type = "S"
  }
}

# Permiso de las Lambdas de action group para leer/escribir en la tabla de tickets
resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name = "${var.project_name}-lambda-dynamodb-access"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.tickets.arn
    }]
  })
}

data "archive_file" "create_ticket" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/create_ticket"
  output_path = "${path.module}/lambda/create_ticket.zip"
}

resource "aws_lambda_function" "create_ticket" {
  function_name = "${var.project_name}-create-ticket-${var.environment}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.create_ticket.output_path
  source_code_hash = data.archive_file.create_ticket.output_base64sha256

  environment {
    variables = {
      TICKETS_TABLE_NAME = aws_dynamodb_table.tickets.name
    }
  }
}

data "archive_file" "get_ticket_status" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/get_ticket_status"
  output_path = "${path.module}/lambda/get_ticket_status.zip"
}

resource "aws_lambda_function" "get_ticket_status" {
  function_name = "${var.project_name}-get-ticket-status-${var.environment}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.get_ticket_status.output_path
  source_code_hash = data.archive_file.get_ticket_status.output_base64sha256

  environment {
    variables = {
      TICKETS_TABLE_NAME = aws_dynamodb_table.tickets.name
    }
  }
}
