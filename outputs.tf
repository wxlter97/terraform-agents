output "bedrock_agent_role_arn" {
  description = "ARN del rol que usará el Bedrock Agent"
  value       = aws_iam_role.bedrock_agent_role.arn
}

output "lambda_exec_role_arn" {
  description = "ARN del rol de ejecución para las Lambdas de action groups"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "aws_account_id" {
  description = "Cuenta de AWS en la que se está desplegando"
  value       = data.aws_caller_identity.current.account_id
}

output "tfstate_bucket_name" {
  description = "Bucket S3 con el state remoto (usar como `bucket` en el bloque backend \"s3\")"
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_lock_table_name" {
  description = "Tabla DynamoDB de locking del state (usar como `dynamodb_table` en el bloque backend \"s3\")"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "tickets_table_name" {
  description = "Tabla DynamoDB donde las Lambdas de action group guardan/consultan tickets"
  value       = aws_dynamodb_table.tickets.name
}

output "create_ticket_lambda_arn" {
  description = "ARN de la Lambda create_ticket (action group del agente, Módulo 3)"
  value       = aws_lambda_function.create_ticket.arn
}

output "get_ticket_status_lambda_arn" {
  description = "ARN de la Lambda get_ticket_status (action group del agente, Módulo 3)"
  value       = aws_lambda_function.get_ticket_status.arn
}
