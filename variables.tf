variable "aws_region" {
  description = "Región de AWS. Bedrock Agents solo está disponible en algunas regiones (us-east-1, us-west-2, etc.)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar todos los recursos del proyecto."
  type        = string
  default     = "agentinfra"
}

variable "environment" {
  description = "Entorno de despliegue (dev, staging, prod)."
  type        = string
  default     = "dev"
}
