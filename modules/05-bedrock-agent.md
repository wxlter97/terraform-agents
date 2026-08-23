# Módulo 5 — El agente (Bedrock AgentCore, no Bedrock Agents Classic)

## La historia real: por qué no es "Bedrock Agents"

El roadmap original (ver README.md) planeaba este módulo sobre `aws_bedrockagent_agent` —
**Bedrock Agents "Classic"**: declarás instrucciones, modelo, action groups y una Knowledge Base
asociada, y AWS corre todo el bucle de orquestación por vos (ver
[agent-harness.md](agent-harness.md)). El código se escribió así primero. Falló al aplicar:

```
AccessDeniedException: Bedrock Agents is in Maintenance Mode. New agent creation is not
available for accounts without prior service usage.
```

Investigando: **AWS cerró Bedrock Agents Classic a cuentas nuevas el 30 de julio de 2026** y lo
puso en modo mantenimiento — los agentes que ya existían siguen funcionando, pero una cuenta que
nunca usó el servicio antes de esa fecha (esta) no puede crear ninguno, sin excepción. No es un
problema de permisos ni de configuración: es una puerta cerrada a nivel de servicio. El `apply`
no llegó a crear nada (el recurso falló antes de que Terraform pudiera registrar nada en el
state), así que no hubo nada que limpiar — a diferencia del dead end de Aurora en el Módulo 4.

El reemplazo que documenta AWS es **Amazon Bedrock AgentCore**, y no es un simple cambio de
nombre de recurso: Bedrock Agents Classic era 100% declarativo (vos describís el agente, AWS lo
ejecuta); AgentCore en su forma general requiere escribir código del agente (Python/TypeScript
con un framework como Strands Agents) que corre en un container administrado. Por suerte existe
un término medio: `aws_bedrockagentcore_harness`, que sí es declarativo — el sucesor más directo
de `aws_bedrockagent_agent` — y es lo que se usó acá.

## Qué se construyó

Arquitectura completa, sin escribir código de agente propio:

- **`aws_bedrockagentcore_harness.helpdesk`**: el agente. `system_prompt` (mismas instrucciones
  en español que se habían escrito para la versión Classic), `model.bedrock_model_config.model_id`
  apuntando a un inference profile de Claude Haiku 4.5, y un solo `tool` de tipo
  `agentcore_gateway` que expone las tres tools de abajo.
- **`aws_bedrockagentcore_gateway.helpdesk`**: el punto de integración MCP entre el harness y las
  Lambdas. `authorizer_type = "AWS_IAM"` (SigV4, sin Cognito/JWT — mismo patrón de auth que el
  resto del proyecto).
- **`aws_bedrockagentcore_gateway_target`** × 3 (`create-ticket`, `get-ticket-status`,
  `query-faqs`): cada uno envuelve una Lambda como tool MCP, con su `input_schema` declarado
  inline (nombre del tool, descripción, parámetros).
- **Lambda nueva: `query_faqs`** ([lambda/query_faqs/index.py](../lambda/query_faqs/index.py)):
  puente hacia la Knowledge Base del Módulo 4 vía `bedrock-agent-runtime:Retrieve`. No existía en
  el Módulo 3 — AgentCore no tiene un tipo de tool nativo para "Knowledge Base" (a diferencia de
  Bedrock Agents Classic, que la asociaba directo al agente), así que necesita este mismo patrón
  de Lambda-detrás-de-Gateway que las otras dos tools.
- **Dos roles IAM nuevos** (`gateway_execution_role`, `harness_execution_role`) — el harness y el
  gateway son servicios distintos con distinto trust principal
  (`bedrock-agentcore.amazonaws.com`), separados de `bedrock_agent_role` (Módulo 1, ahora sin
  uso — ver nota en [iam.tf](../iam.tf)).
- **`create_ticket`/`get_ticket_status` reescritas** ([lambda/create_ticket/index.py](../lambda/create_ticket/index.py),
  [lambda/get_ticket_status/index.py](../lambda/get_ticket_status/index.py)): el contrato de
  evento/respuesta de un Gateway target es distinto al de un action group de Bedrock Agents
  Classic (ver tabla abajo) — el código viejo directamente no hubiera funcionado.

## El contrato de evento cambió

| | Bedrock Agents Classic (código original, Módulo 3) | AgentCore Gateway (código actual) |
|---|---|---|
| Evento de entrada | `{"parameters": [{"name": "x", "value": "y"}], "actionGroup": "...", "function": "..."}` | `{"x": "y"}` — las propiedades del `input_schema` directo, plano |
| Respuesta esperada | `{"messageVersion": "1.0", "response": {"actionGroup": ..., "functionResponse": {"responseBody": {"TEXT": {"body": "..."}}}}}` | Cualquier JSON válido, sin wrapper |

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **Maintenance mode** | Estado en el que AWS deja un servicio (acá, Bedrock Agents Classic) sin nuevas altas ni desarrollo — lo que ya existe sigue andando, nada nuevo puede crearse. |
| **AgentCore Harness** | El recurso declarativo de AgentCore más parecido a un "agente" tradicional: instrucciones + modelo + tools, corriendo sobre un runtime administrado por AWS (sin container propio, salvo que se necesite uno custom). |
| **AgentCore Gateway** | Traduce el protocolo MCP (Model Context Protocol) a invocaciones de recursos reales — acá, Lambdas. Es la pieza que reemplaza a los "action groups" de Bedrock Agents Classic. |
| **Gateway target** | Un tool puntual expuesto por un Gateway — en este proyecto, cada uno envuelve una Lambda con su schema de entrada. |
| **MCP (Model Context Protocol)** | Protocolo estándar (no específico de AWS) para que un modelo/agente descubra y llame herramientas externas. |
| **Inference profile** | Un identificador que enruta la invocación de un modelo a través de varias regiones — necesario acá porque Claude Haiku 4.5 solo está disponible como `INFERENCE_PROFILE`, no on-demand directo, en esta cuenta/región. |

## Decisiones de diseño

- **Por qué `execution_role_arn` del harness es un rol nuevo y no `bedrock_agent_role`**: distinto
  trust principal (`bedrock-agentcore.amazonaws.com` vs `bedrock.amazonaws.com`) — son servicios
  de AWS diferentes, cada uno con su propia identidad de servicio.
- **Por qué el Gateway usa `authorizer_type = "AWS_IAM"`**: evita meter Cognito/JWT solo para un
  proyecto de aprendizaje — SigV4 con el rol de ejecución del harness es coherente con el patrón
  de autenticación que ya usa el resto del proyecto (IAM roles en todos lados, sin usuarios ni
  API keys).
- **Por qué no se usó un Policy Engine (Cedar) en el Gateway**: es una feature opcional de
  autorización fina (qué tool puede llamar quién, bajo qué condiciones) — fuera de alcance para
  un agente de un solo caller con tools ya acotadas por IAM.
- **Race condition de IAM al aplicar**: el primer `apply` de este módulo falló en el tercer
  `gateway_target` (`query-faqs`) con `Gateway service is not authorized to perform AssumeRole on
  Gateway role` — mismo rol que los otros dos, que sí se crearon bien. Es propagación de IAM (el
  trust policy tarda unos segundos en propagarse globalmente); los dos primeros targets tardaron
  10-19s en crearse (tiempo de sobra), el tercero arrancó casi inmediatamente después del rol. Un
  segundo `apply` lo resolvió sin tocar nada — vale la pena saber que este tipo de error en
  recursos recién creados suele ser timing, no configuración, antes de salir a depurar de más.

## Comandos usados para desplegar y verificar

```bash
terraform init
terraform plan
terraform apply

# Verificación (control plane — funciona con el AWS CLI actual)
terraform output harness_id
aws bedrock-agentcore-control get-harness --harness-id <harness_id>
aws bedrock-agentcore-control list-gateway-targets --gateway-identifier $(terraform output -raw gateway_id)
```

## Pendiente: invocación end-to-end

El harness quedó verificado como `READY` (control plane), con el modelo, el system prompt y las
tres tools exactamente como se configuraron — pero no se pudo probar una conversación real
end-to-end en esta sesión. La API de invocación (`InvokeHarness`) es tan nueva que **el AWS CLI
todavía no la expone** — confirmado probando `aws bedrock-agentcore invoke-agent-runtime`
directamente contra el runtime interno del harness, que devuelve explícitamente:

```
ValidationException: The agent runtime ... is managed by a harness and cannot be invoked
directly. Use the InvokeHarness API with the relevant harness ID instead.
```

Es un gap real de tooling (confirmado con el error del servicio, no una suposición), no un
problema de este proyecto. Para probarlo hace falta el SDK (`boto3`, método `invoke_harness`) o la
consola de AWS. En esta máquina, además, la instalación de Python tiene un problema de linkeo de
`libexpat` que impidió instalar `boto3` para probarlo — un problema del entorno local, no del
código. Próximos pasos posibles: probar desde la consola de Bedrock AgentCore, o desde otra
máquina/entorno con `boto3` funcionando:

```python
import boto3, uuid
client = boto3.client("bedrock-agentcore", region_name="us-east-1")
response = client.invoke_harness(
    harnessArn="<harness_arn>",  # terraform output harness_arn
    runtimeSessionId=str(uuid.uuid4()),
    messages=[{"role": "user", "content": [{"text": "¿Cómo reseteo mi contraseña?"}]}],
)
```

## Costo

- **Harness**: se factura por invocación/tiempo de sesión — sin uso, sin costo (a diferencia de
  Aurora, acá no hay nada "corriendo" en reposo).
- **Gateway**: factura por request. Volumen de pruebas de este proyecto, centavos.
- **Modelo (Claude Haiku 4.5 vía inference profile)**: por token, igual que cualquier invocación
  de Bedrock — el motivo de elegir el modelo "económico" que pide el README.

## Caso de uso (contexto)

Con este módulo, el agente de soporte descripto en el [README](../README.md) queda completo de
punta a punta: recibe una pregunta, decide si consultar `query_faqs` (Módulo 4) o crear/consultar
un ticket vía `create_ticket`/`get_ticket_status` (Módulo 3), todo orquestado por el harness sin
código de agente propio. Ver [agent-harness.md](agent-harness.md) para cómo estas piezas encajan
en el concepto general de "harness".
