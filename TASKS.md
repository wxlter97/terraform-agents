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

## ✅ Módulo 4 — Knowledge Base (RAG) (completado)

- [x] Bucket S3 para el contenido de FAQ (cifrado; no necesita versionado como el de state)
- [x] Redactar/subir contenido inicial de FAQ (texto plano o Markdown) alineado al caso de uso
      helpdesk (ver README.md "Caso de uso")
- [x] Elegir vector store — terminó siendo **S3 Vectors**, no OpenSearch Serverless ni Aurora
      (el plan original, Aurora + pgvector, resultó ser un dead end en esta cuenta — ver
      `modules/04-knowledge-base.md` para la historia completa). Requirió subir el provider AWS
      de `~> 5.0` a `~> 6.0`.
- [x] Rol IAM para la Knowledge Base (lectura de S3 + acceso al vector store)
- [x] `aws_bedrockagent_knowledge_base` + `aws_bedrockagent_data_source`
- [x] Trigger de ingesta inicial (sync job) y verificación manual de una query — quedó bloqueado
      un rato por verificación de cuenta nueva de AWS, se resolvió solo (como avisaba el mensaje)
      y corrió limpio horas después, durante el Módulo 6: 3/3 documentos indexados, una consulta
      real devolvió el contenido exacto de la FAQ.
- [x] `modules/04-knowledge-base.md`

## ✅ Módulo 5 — El agente (AgentCore, no Bedrock Agents Classic) (completado, salvo un pendiente externo)

- [x] ~~`aws_bedrockagent_agent` (Bedrock Agents Classic)~~ — **bloqueado a nivel de servicio**:
      esta cuenta no puede crear agentes Classic (maintenance mode desde el 30/07/2026, cuentas
      sin uso previo no tienen acceso). Pivotado a **Bedrock AgentCore** — ver
      `modules/05-bedrock-agent.md` para la historia completa.
- [x] `aws_bedrockagentcore_harness`: instrucciones (system prompt), modelo (Claude Haiku 4.5 vía
      inference profile), rol de ejecución propio
- [x] `aws_bedrockagentcore_gateway` + 3 `aws_bedrockagentcore_gateway_target` (create_ticket,
      get_ticket_status, query_faqs) — el reemplazo de "action groups" en AgentCore
- [x] Lambda nueva `query_faqs` — puente hacia la Knowledge Base del Módulo 4 (AgentCore no
      tiene tool nativo de Knowledge Base)
- [x] Reescritura de `create_ticket`/`get_ticket_status`: el contrato de evento/respuesta de un
      Gateway target de AgentCore es distinto al de un action group de Bedrock Agents Classic
- [x] `aws_lambda_permission` × 3 con `source_arn` del **Gateway** (no del agente/alias — ya no
      hay alias en este diseño)
- [x] Probar invocación manual end-to-end — el AWS CLI no tiene `invoke-harness`, pero se
      confirmó (Lambda de diagnóstico descartable) que el boto3 que trae el runtime de Lambda
      (`python3.12`, boto3 1.42.97) sí soporta `invoke_harness` — la prueba real end-to-end se
      hizo desde la Lambda proxy del Módulo 6, ver esa sección.
- [x] `modules/05-bedrock-agent.md`

## ✅ Módulo 6 — API Gateway + Lambda proxy (completado — probado end-to-end de verdad)

- [x] Lambda proxy que invoca al harness (`InvokeHarness`, Módulo 5 — no `InvokeAgent`, eso era
      Bedrock Agents Classic) y devuelve la respuesta
- [x] `aws_apigatewayv2_api` (HTTP API) + integración + ruta
- [x] Permisos IAM: API Gateway → Lambda proxy → `bedrock-agentcore:InvokeHarness` +
      `bedrock-agentcore:InvokeAgentRuntime` (ambos requeridos, ver modules/05-bedrock-agent.md)
- [x] Probar el endpoint end-to-end con `curl` — encontró y arregló **dos** permisos IAM reales
      faltantes (AgentCore Memory, activación de AWS Marketplace para el modelo) y requirió
      completar a mano el formulario de "use case" de Anthropic en la consola. Los tres bloqueos
      están documentados en `modules/06-api-gateway.md`. `POST /chat` responde 200 con una
      respuesta real y correcta, citando el contenido exacto de la FAQ del Módulo 4 y recordando
      un ticket creado en una invocación anterior (confirma que AgentCore Memory funciona).
- [x] `modules/06-api-gateway.md`

## ✅ Módulo 7 — Observabilidad (completado)

- [x] Log groups de CloudWatch para las Lambdas y el runtime del harness — retención de 14 días,
      importados los que ya existían de invocaciones anteriores (ver `modules/07-observabilidad.md`
      para el porqué y los comandos exactos de `terraform import`)
- [x] Alarms básicas: errores + throttles por Lambda (8), más 5xx + latencia p90 del endpoint
      `/chat` (2) — 10 en total, dentro del free tier siempre-gratuito de CloudWatch Alarms
- [x] Budget de AWS ($5/mes, filtrado por tag `Project`) — cierra el pendiente que quedó anotado en
      el Módulo 6 sobre el endpoint público sin auth ni throttle
- [x] `modules/07-observabilidad.md`

## ✅ Módulo 8 — CI/CD (completado, salvo probarlo con un PR real)

- [x] `cicd.tf`: OIDC provider + rol IAM que GitHub Actions asume (sin access keys estáticas)
- [x] `.github/workflows/terraform-plan.yml`: `fmt -check` + `validate` + `plan` en cada PR contra
      `master`, comentando el resultado (actualiza el mismo comentario, no acumula)
- [x] `.github/workflows/terraform-apply.yml`: solo `workflow_dispatch`, con guard que falla si no
      se corre desde `master` — nunca automático al mergear
- [x] Configuración manual (repo variable `AWS_CI_ROLE_ARN`) — hecha con `gh variable set`
- [ ] **Pendiente**: los dos workflows están escritos y el `terraform validate`/`plan` local pasa,
      pero no se probaron corriendo de verdad en GitHub Actions — hace falta abrir un PR real
      contra `master` para eso (se le preguntó al usuario antes de hacerlo, repo es público).
- [x] `modules/08-cicd.md`

## Deuda / pendientes menores

- [ ] `providers.tf` tiene un warning de Terraform: el parámetro `dynamodb_table` del backend
      `s3` (Módulo 2) está deprecado a favor de `use_lockfile`. No urgente (sigue funcionando),
      pero conviene migrarlo en algún momento — no se tocó en el Módulo 4 para no mezclar cambios
      no relacionados en el mismo apply.
- [ ] El endpoint `POST /chat` (Módulo 6) sigue sin autenticación ni throttle — a propósito para
      este proyecto de aprendizaje (ver nota de seguridad en `modules/06-api-gateway.md`). El
      budget del Módulo 7 avisa si el gasto se dispara, pero no lo previene — un throttle/usage
      plan o auth (IAM o JWT) siguen fuera del roadmap salvo que se pida explícitamente.
- [ ] Confirmar la suscripción de SNS por mail (wxlter.97@gmail.com) — quedó en
      `PendingConfirmation` al terminar el Módulo 7, las alarms no notifican hasta que se confirme.

## Cómo usar este archivo

1. Antes de empezar un módulo, revisar su sección acá para saber exactamente qué falta.
2. Marcar cada tarea `[x]` a medida que se completa (no esperar a terminar todo el módulo).
3. Al cerrar un módulo: crear `modules/NN-nombre.md`, actualizar la tabla en `modules/README.md`,
   y si cambia el estado general del proyecto, actualizar el resumen de módulos completados en
   [CLAUDE.md](CLAUDE.md).
