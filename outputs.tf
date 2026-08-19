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
