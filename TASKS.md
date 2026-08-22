# TASKS.md — estado de implementación y cola de trabajo

Fuente de verdad para "qué falta" en este proyecto, a nivel de tarea concreta (más granular que
la tabla de estado en [modules/README.md](modules/README.md), que es por módulo completo). Se
actualiza a medida que se completan tareas — marcar `[x]` y, si aplica, agregar una nota corta.

Convención: cada módulo completado termina con su archivo `modules/NN-nombre.md` (ver
[CLAUDE.md](CLAUDE.md)) — esa es la tarea final de cada sección.

## ✅ Módulo 1 — Fundamentos (completado)

- [x] `providers.tf`: provider AWS + backend local inicial
- [x] `variables.tf`: `aws_region`, `project_name`, `environment`
- [x] `aws_iam_role.bedrock_agent_role` + policy `bedrock:InvokeModel`
- [x] `aws_iam_role.lambda_exec_role` + `AWSLambdaBasicExecutionRole`
- [x] Policy `bedrock_invoke_lambda` (Bedrock → Lambdas `${project_name}-*`)
- [x] `outputs.tf` con ARNs de roles
- [x] `modules/01-fundamentos.md`

## ✅ Módulo 2 — Backend remoto (completado)

- [x] `backend.tf`: bucket S3 (versionado, cifrado, `prevent_destroy`) + tabla DynamoDB de lock
- [x] Migración de backend `local` → `s3` (`terraform init -migrate-state`)
- [x] `outputs.tf`: `tfstate_bucket_name`, `tfstate_lock_table_name`
- [x] `.gitignore`: `*.tfstate*`
- [x] `modules/02-backend-remoto.md`

## ✅ Módulo 3 — Action groups (completado)

- [x] `aws_dynamodb_table.tickets` (`PAY_PER_REQUEST`, hash key `ticket_id`)
- [x] Policy `lambda_dynamodb_access` (PutItem/GetItem sobre `tickets`)
- [x] Lambda `create_ticket` ([lambda/create_ticket/index.py](lambda/create_ticket/index.py))
- [x] Lambda `get_ticket_status` ([lambda/get_ticket_status/index.py](lambda/get_ticket_status/index.py))
- [x] `modules/03-action-groups.md`

## 📝 Concepto — Agent harness (completado, no numerado)

- [x] `modules/agent-harness.md` — qué es un harness de agente y mapeo a piezas de Bedrock Agents
- [x] Referenciado desde `modules/README.md` y `CLAUDE.md`

## ✅ Módulo 4 — Knowledge Base (RAG) (completado, salvo un pendiente externo)

- [x] Bucket S3 para el contenido de FAQ (cifrado; no necesita versionado como el de state)
- [x] Redactar/subir contenido inicial de FAQ (texto plano o Markdown) alineado al caso de uso
      helpdesk (ver README.md "Caso de uso")
- [x] Elegir vector store — terminó siendo **S3 Vectors**, no OpenSearch Serverless ni Aurora
      (el plan original, Aurora + pgvector, resultó ser un dead end en esta cuenta — ver
      `modules/04-knowledge-base.md` para la historia completa). Requirió subir el provider AWS
      de `~> 5.0` a `~> 6.0`.
- [x] Rol IAM para la Knowledge Base (lectura de S3 + acceso al vector store)
- [x] `aws_bedrockagent_knowledge_base` + `aws_bedrockagent_data_source`
- [ ] Trigger de ingesta inicial (sync job) y verificación manual de una query — **bloqueado**:
      `start-ingestion-job` devuelve `ValidationException` por verificación de cuenta nueva de
      AWS ("normally takes less than 2 hours"). No es un problema de config; reintentar
      `aws bedrock-agent start-ingestion-job` más tarde (comando exacto en el módulo doc).
- [x] `modules/04-knowledge-base.md`

## ⏳ Módulo 5 — Bedrock Agent + Agent Alias

- [ ] `aws_bedrockagent_agent`: instrucciones (system prompt) del agente helpdesk, foundation
      model, `bedrock_agent_role`
- [ ] Conectar action group (Lambdas del Módulo 3) vía
      `aws_bedrockagent_agent_action_group` + schema de funciones (`create_ticket`,
      `get_ticket_status`)
- [ ] `aws_lambda_permission` con `source_arn` del agente/alias — permiso pendiente desde el
      Módulo 3 (ver comentario en [action-groups.tf](action-groups.tf))
- [ ] Asociar la Knowledge Base del Módulo 4 al agente
- [ ] `aws_bedrockagent_agent_alias`
- [ ] Probar invocación manual (`aws bedrock-agent-runtime invoke-agent`) con una pregunta
      resuelta por KB y otra que dispare `create_ticket`
- [ ] `modules/05-bedrock-agent.md`

## ⏳ Módulo 6 — API Gateway + Lambda proxy

- [ ] Lambda proxy que invoca al Agent Alias (`InvokeAgent`) y devuelve la respuesta
- [ ] `aws_apigatewayv2_api` (HTTP API) + integración + ruta
- [ ] Permisos IAM: API Gateway → Lambda proxy → `bedrock-agent-runtime:InvokeAgent`
- [ ] Probar el endpoint end-to-end con `curl`
- [ ] `modules/06-api-gateway.md`

## ⏳ Módulo 7 — Observabilidad

- [ ] Log groups de CloudWatch para las Lambdas y trace del agente
- [ ] Alarms básicas (errores de Lambda, throttles, latencia del agente)
- [ ] `modules/07-observabilidad.md`

## ⏳ Módulo 8 — CI/CD

- [ ] Workflow de GitHub Actions: `terraform fmt -check` + `terraform validate` en cada PR
- [ ] `terraform plan` comentado automáticamente en el PR
- [ ] `apply` manual o gateado (no automático a `main` sin revisión)
- [ ] `modules/08-cicd.md`

## Deuda / pendientes menores

- [ ] Correr `start-ingestion-job` de la Knowledge Base del Módulo 4 una vez que pase la
      verificación de cuenta de AWS (ver esa sección arriba) — sin esto, la KB existe pero no
      tiene vectores cargados todavía.
- [ ] `providers.tf` tiene un warning de Terraform: el parámetro `dynamodb_table` del backend
      `s3` (Módulo 2) está deprecado a favor de `use_lockfile`. No urgente (sigue funcionando),
      pero conviene migrarlo en algún momento — no se tocó en el Módulo 4 para no mezclar cambios
      no relacionados en el mismo apply.

## Cómo usar este archivo

1. Antes de empezar un módulo, revisar su sección acá para saber exactamente qué falta.
2. Marcar cada tarea `[x]` a medida que se completa (no esperar a terminar todo el módulo).
3. Al cerrar un módulo: crear `modules/NN-nombre.md`, actualizar la tabla en `modules/README.md`,
   y si cambia el estado general del proyecto, actualizar el resumen de "Módulos 1-3 done" en
   [CLAUDE.md](CLAUDE.md).
