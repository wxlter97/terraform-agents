# /modules — notas de aprendizaje

Esta carpeta **no contiene módulos de Terraform reutilizables** (este proyecto usa un único
root module — ver [CLAUDE.md](../CLAUDE.md)). Es un registro de aprendizaje: un archivo por cada
módulo del roadmap definido en [README.md](../README.md), con lo que se construyó, la
terminología nueva y los conceptos clave de ese paso.

La idea es que cada archivo quede como referencia propia para repasar más adelante, no como
documentación formal del código (eso ya lo cubren los comentarios en los `.tf` y el README).

## Índice

| Archivo | Módulo | Estado |
|---|---|---|
| [01-fundamentos.md](01-fundamentos.md) | 1. Fundamentos (IAM) | ✅ Completado |
| [02-backend-remoto.md](02-backend-remoto.md) | 2. Backend remoto (S3 + DynamoDB) | ✅ Completado |
| [03-action-groups.md](03-action-groups.md) | 3. Lambda action groups | ✅ Completado |
| [04-knowledge-base.md](04-knowledge-base.md) | 4. Knowledge Base (RAG) | ✅ Completado |
| [05-bedrock-agent.md](05-bedrock-agent.md) | 5. El agente (Bedrock AgentCore, no Bedrock Agents Classic — ver el archivo) | ✅ Completado |
| [06-api-gateway.md](06-api-gateway.md) | 6. API Gateway + Lambda proxy | ✅ Completado |
| `07-observabilidad.md` | 7. CloudWatch logs y alarms | ⏳ Pendiente |
| `08-cicd.md` | 8. CI/CD (GitHub Actions) | ⏳ Pendiente |

Cada archivo nuevo se agrega al terminar el módulo correspondiente.

## Notas conceptuales (no atadas a un módulo numerado)

| Archivo | Tema |
|---|---|
| [agent-harness.md](agent-harness.md) | Qué es un "agent harness" (bucle de orquestación, tools, estado de sesión) y cómo se mapea a los recursos de Bedrock Agents de este proyecto. Preparación para el Módulo 5. |
