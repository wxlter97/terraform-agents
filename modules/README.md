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
| `03-action-groups.md` | 3. Lambda action groups | ⏳ Pendiente |
| `04-knowledge-base.md` | 4. Knowledge Base (RAG) | ⏳ Pendiente |
| `05-bedrock-agent.md` | 5. Bedrock Agent + Alias | ⏳ Pendiente |
| `06-api-gateway.md` | 6. API Gateway + Lambda proxy | ⏳ Pendiente |
| `07-observabilidad.md` | 7. CloudWatch logs y alarms | ⏳ Pendiente |
| `08-cicd.md` | 8. CI/CD (GitHub Actions) | ⏳ Pendiente |

Cada archivo nuevo se agrega al terminar el módulo correspondiente.
