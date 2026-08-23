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

output "faqs_bucket_name" {
  description = "Bucket S3 con el contenido de FAQ que ingesta la Knowledge Base (Módulo 4)"
  value       = aws_s3_bucket.faqs.id
}

output "kb_vector_bucket_name" {
  description = "Vector bucket de S3 Vectors que respalda la Knowledge Base (Módulo 4)"
  value       = aws_s3vectors_vector_bucket.kb.vector_bucket_name
}

output "kb_vector_index_arn" {
  description = "ARN del índice de S3 Vectors usado como storage_configuration de la Knowledge Base (Módulo 4)"
  value       = aws_s3vectors_index.kb.index_arn
}

output "knowledge_base_id" {
  description = "ID de la Knowledge Base de Bedrock (Módulo 4)"
  value       = aws_bedrockagent_knowledge_base.helpdesk.id
}

output "knowledge_base_data_source_id" {
  description = "ID del data source S3 de la Knowledge Base, necesario para disparar la ingesta manual (Módulo 4)"
  value       = aws_bedrockagent_data_source.faqs.data_source_id
}

output "query_faqs_lambda_arn" {
  description = "ARN de la Lambda query_faqs (puente Gateway -> Knowledge Base, Módulo 5)"
  value       = aws_lambda_function.query_faqs.arn
}

output "gateway_id" {
  description = "ID del AgentCore Gateway que expone las tres tool Lambdas (Módulo 5)"
  value       = aws_bedrockagentcore_gateway.helpdesk.gateway_id
}

output "gateway_arn" {
  description = "ARN del AgentCore Gateway (Módulo 5)"
  value       = aws_bedrockagentcore_gateway.helpdesk.gateway_arn
}

output "harness_id" {
  description = "ID del harness (el agente) — usar para invoke-harness (Módulo 5)"
  value       = aws_bedrockagentcore_harness.helpdesk.harness_id
}

output "harness_arn" {
  description = "ARN del harness (Módulo 5)"
  value       = aws_bedrockagentcore_harness.helpdesk.arn
}
