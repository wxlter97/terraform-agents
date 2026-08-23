# Módulo 6 — API Gateway + Lambda proxy

## Qué se construyó

- **`api-gateway.tf`**:
  - `aws_iam_role.api_proxy_role` + policy: rol de ejecución de la Lambda proxy, con los dos
    permisos que documenta AWS para `InvokeHarness` (`bedrock-agentcore:InvokeHarness` +
    `bedrock-agentcore:InvokeAgentRuntime`, ambos requeridos — ver
    [modules/05-bedrock-agent.md](05-bedrock-agent.md)) sobre el ARN del harness.
  - `aws_lambda_function.chat_proxy`: la Lambda que traduce HTTP → `InvokeHarness`.
  - `aws_apigatewayv2_api` (HTTP API, más simple/barata que una REST API) + `..._stage` (`$default`,
    auto-deploy) + `..._integration` (AWS_PROXY, payload format 2.0) + `..._route` (`POST /chat`).
  - `aws_lambda_permission` para que API Gateway invoque la Lambda.
- **`lambda/chat_proxy/index.py`**: recibe `{"message": "...", "session_id": "opcional"}`, llama
  `invoke_harness` del cliente `bedrock-agentcore` de boto3, itera el stream de respuesta y
  devuelve `{"session_id", "reply", "stop_reason", "usage"}`.

## Antes de escribir código: verificar que el SDK soporta la API

`InvokeHarness` es tan nueva que el AWS CLI no la tiene (ver Módulo 5). Antes de asumir que había
que hacer una llamada HTTP firmada a mano, se desplegó una Lambda de diagnóstico descartable (no
gestionada por Terraform, borrada después) que simplemente reportaba
`hasattr(boto3.client("bedrock-agentcore"), "invoke_harness")` — el runtime administrado de Lambda
(`python3.12`) trae boto3 1.42.97, que **sí** la soporta. Evitó escribir una implementación mucho
más compleja (SigV4 a mano) que no hacía falta. Una segunda Lambda de diagnóstico volcó el shape
exacto del request/response de `InvokeHarness` (`client.meta.service_model.operation_model(...)`)
antes de escribir `index.py` — la respuesta es un **stream de eventos** al estilo Bedrock Converse
Stream, no un JSON plano.

## Dos bugs reales encontrados recién al invocar de verdad

El primer `terraform apply` de este módulo salió limpio (`terraform plan` no había mostrado nada
raro), pero la primera invocación real vía `curl` falló — dos veces, con dos causas distintas:

1. **Permiso IAM faltante para AgentCore Memory.** El harness aprovisiona automáticamente una
   memoria por default (historial de conversación por sesión) aunque el bloque `memory` no se
   configure explícitamente en `aws_bedrockagentcore_harness` — al escribir el Módulo 5 se asumió
   que ese permiso era "opcional" (la doc de AWS lo separa en una sección de features opcionales)
   y se omitió. `InvokeHarness` fallaba con `AccessDeniedException` en `bedrock-agentcore:
   ListEvents` sobre el recurso `memory/<id>`. Se corrigió agregando el statement `AgentCoreMemory`
   a `harness_execution_policy` en `bedrock-agentcore.tf` — con un wildcard de recurso
   (`memory/*`) porque el patrón de ARN real que crea AWS (`memory/<harnessId>-<sufijo>`) no
   coincide exactamente con el placeholder que documenta AWS (`memory/harness_<nombre>_*`).
2. **Cuenta sin el formulario de "use case" de Anthropic completado.** Una vez resuelto el permiso
   de Memory, la invocación llegó hasta el modelo y falló con
   `ResourceNotFoundException: Model use case details have not been submitted for this account.
   Fill out the Anthropic use case details form before using the model.` — un requisito de
   compliance de Anthropic/AWS para cuentas que invocan modelos Anthropic por primera vez,
   completamente aparte del "account verification" del Módulo 4. **No es un problema de Terraform
   ni de este código** — es un formulario de negocio/uso que representa una declaración de la
   cuenta, así que queda pendiente para completar manualmente (ver "Pendiente" abajo), no algo que
   se pueda resolver con más permisos IAM.

Ninguno de los dos apareció en `terraform plan`/`apply` porque son errores de **runtime** (permisos
IAM evaluados al invocar, no al crear el rol; el gate de Anthropic se evalúa al invocar el modelo)
— otro recordatorio de que "aplicó sin errores" no es lo mismo que "funciona", sobre todo con
servicios nuevos donde la documentación puede no reflejar el comportamiento real todavía.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **HTTP API (API Gateway v2)** | Versión más simple y barata de API Gateway frente a REST API (v1) — menos features (sin API keys/usage plans nativos), pero alcanza para un proxy Lambda simple. |
| **Integración AWS_PROXY** | API Gateway le pasa el request crudo a la Lambda tal cual, y espera de vuelta un objeto con `statusCode`/`headers`/`body` — la Lambda controla toda la respuesta HTTP. |
| **Payload format version 2.0** | El shape simplificado de evento/respuesta para integraciones Lambda de HTTP API (más chico que el 1.0, que imita el formato viejo de REST API). |
| **AgentCore Memory (default)** | Instancia de memoria que un harness aprovisiona automáticamente para trackear el historial de una sesión de conversación — no hace falta crearla ni referenciarla a mano, pero sí darle permisos IAM al rol de ejecución. |
| **Anthropic use case form** | Formulario de compliance que declara para qué se van a usar los modelos Anthropic en la cuenta — requisito único por cuenta, separado del "account verification" genérico de Bedrock (Módulo 4). |

## Pendiente: completar el formulario de use case de Anthropic

Para que el endpoint funcione de punta a punta hace falta completar esto **manualmente en la
consola** (es una declaración de la cuenta, no algo que este proyecto deba automatizar ni asumir
en tu nombre):

1. Consola de AWS → Bedrock → Model catalog (o Playground) → elegir cualquier modelo Anthropic.
2. Completar el formulario de "use case details" que aparece.
3. Esperar unos minutos (el error menciona hasta 15) y reintentar.

Existe una API (`aws bedrock put-use-case-for-model-access --form-data <blob>`) pero requiere un
payload con la información de uso de la cuenta — no es algo para completar con datos inventados.

## Comandos usados para desplegar y verificar

```bash
terraform init
terraform plan
terraform apply

terraform output api_endpoint

curl -X POST "$(terraform output -raw api_endpoint)/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "How do I reset my password?"}'

# Debug: logs de la Lambda proxy
aws logs tail /aws/lambda/agentinfra-chat-proxy-dev --since 5m
```

## Costo

- **API Gateway (HTTP API)**: dentro del free tier siempre gratuito para el volumen de este
  proyecto (1M requests/mes gratis en el free tier de 12 meses, y HTTP API es más barato que REST
  API incluso fuera de free tier).
- **Lambda proxy**: mismo régimen free-tier que las demás Lambdas del proyecto.
- **Bedrock (modelo + tools)**: por token/request, igual que siempre.

## Nota de seguridad (no atada al costo)

El endpoint `POST /chat` no tiene autenticación (`authorization_type` default = `NONE`), a
propósito, para que coincida con la descripción del caso de uso ("cualquier front-end o script
puede llamar"). Eso significa que cualquiera con la URL puede generar invocaciones de Bedrock (con
costo) sin límite — aceptable para un proyecto de aprendizaje con `apply`/`destroy` frecuentes, no
para un uso real. El Módulo 7 (observabilidad) es un buen lugar para al menos agregar alarms de
gasto; un throttle/usage plan o autenticación (IAM o JWT) quedan fuera del roadmap actual salvo que
se pida explícitamente.

## Caso de uso (contexto)

Con este módulo, el proyecto llega al punto que describe el [README](../README.md): un endpoint
HTTP público al que cualquier cliente puede pegarle para hablar con el agente de soporte completo
(FAQs vía RAG + creación/consulta de tickets), sin necesitar credenciales de AWS ni conocer nada
de Bedrock del lado del caller.
