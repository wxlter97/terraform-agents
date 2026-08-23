# Módulo 3 — Action groups (Lambdas del agente)

## Qué se construyó

- **`action-groups.tf`**:
  - `aws_dynamodb_table.tickets`: tabla de tickets de soporte, `billing_mode = "PAY_PER_REQUEST"`,
    clave de partición `ticket_id` (string).
  - `aws_iam_role_policy.lambda_dynamodb_access`: policy inline sobre `lambda_exec_role` (creado
    en el Módulo 1) que permite `dynamodb:PutItem` y `dynamodb:GetItem` solo sobre esta tabla.
  - `data.archive_file.create_ticket` / `data.archive_file.get_ticket_status`: empaquetan el
    código Python de cada Lambda en un `.zip` en el momento del `plan`/`apply` (provider
    `archive`, agregado a `providers.tf` en este módulo).
  - `aws_lambda_function.create_ticket` / `aws_lambda_function.get_ticket_status`: runtime
    `python3.12`, usan `lambda_exec_role`, y reciben el nombre de la tabla de tickets vía variable
    de entorno `TICKETS_TABLE_NAME`.
- **`lambda/create_ticket/index.py`**: recibe los parámetros que Bedrock extrajo del mensaje del
  usuario (`event["parameters"]`), genera un `ticket_id` con `uuid.uuid4()`, guarda el item en
  DynamoDB con `status = "open"`, y devuelve la respuesta con el shape que espera un action group
  de Bedrock Agents.
- **`lambda/get_ticket_status/index.py`**: recibe un `ticket_id` como parámetro, lo busca en
  DynamoDB y devuelve su `status`, o un error si no existe.
- **`outputs.tf`**: `tickets_table_name`, `create_ticket_lambda_arn`, `get_ticket_status_lambda_arn`.

Ambas Lambdas comparten el mismo helper `_agent_response()` (duplicado a propósito en cada
`index.py` — no hay todavía una capa compartida entre Lambdas en este proyecto) que arma el
`dict` de respuesta con la forma exacta que Bedrock Agents espera de una función de action group:
`messageVersion`, `response.actionGroup`, `response.function`,
`response.functionResponse.responseBody.TEXT.body` (el body va serializado como string JSON
dentro de `TEXT.body`, no como objeto).

## Lo que falta a propósito (queda para el Módulo 5)

Estas Lambdas quedan **desplegadas pero inertes**: nada externo puede invocarlas todavía.

- No existe el recurso `aws_bedrockagent_agent` ni su action group — sin eso, Bedrock no sabe que
  estas funciones existen ni cuándo llamarlas.
- Falta el `aws_lambda_permission` (resource-based policy en cada Lambda) que autorice a Bedrock a
  invocarlas, con `source_arn` apuntando al Agent Alias. No se puede crear ahora porque ese ARN no
  existe hasta el Módulo 5.
- La policy `bedrock_invoke_lambda` del Módulo 1 (sobre `bedrock_agent_role`, lado *caller*) ya
  cubre el permiso "de salida"; el `aws_lambda_permission` de este punto es el permiso "de
  entrada" (resource-based) del lado de la Lambda — Lambda necesita **ambos** para que una
  invocación cross-service funcione.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **Action group** | Agrupación de Bedrock que expone una o más funciones (acá, Lambdas) como *tools* que el agente puede invocar, junto con el schema de sus parámetros. |
| **`data "archive_file"`** | Data source de Terraform (provider `archive`) que empaqueta un directorio en un `.zip` en tiempo de plan/apply — evita tener que zippear el código a mano antes de cada `apply`. |
| **`source_code_hash`** | Hash del `.zip` que Terraform usa para detectar si el código de la Lambda cambió (y por lo tanto si hay que actualizarla), independiente de si el resto de la configuración cambió. |
| **Resource-based policy (Lambda)** | Policy adjunta directamente al recurso (la Lambda), a diferencia de una *identity-based policy* adjunta a un rol/usuario. Define **quién más** (qué servicio o cuenta) puede invocar ese recurso puntual. `aws_lambda_permission` es el recurso de Terraform para esto. |
| **Variable de entorno (Lambda)** | Forma de pasarle configuración a una Lambda sin hardcodearla en el código — acá, `TICKETS_TABLE_NAME` para no repetir el nombre de la tabla en el `.py`. |
| **`messageVersion` / `functionResponse`** | Contrato de formato que Bedrock Agents exige en la respuesta de una Lambda de action group — no es libre, tiene que matchear ese shape exacto o el agente no puede parsear el resultado. |

## Conceptos clave

- **Por qué `lambda_exec_role` es uno solo para ambas Lambdas**: las dos hacen operaciones
  equivalentes (leer/escribir la misma tabla), así que comparten rol en vez de tener uno por
  función — mínimo privilegio a nivel de *qué* pueden hacer, no necesariamente uno distinto por
  cada Lambda individual.
- **Por qué el permiso de invocación es de dos vías**: Bedrock necesita permiso para *llamar*
  Lambda (`bedrock_invoke_lambda`, Módulo 1, identity-based en el rol del agente) y la Lambda
  necesita permitir *ser llamada por* Bedrock (`aws_lambda_permission`, resource-based, pendiente
  del Módulo 5). Es el mismo patrón de "dos identidades, dos permisos" que ya apareció en el
  Módulo 1 entre el agente y las Lambdas.
- **Por qué generar el `ticket_id` en la Lambda y no dejarlo elegir al modelo**: un UUID generado
  server-side evita colisiones y evita confiar en que el LLM invente un identificador único y
  válido — la Lambda es la única fuente de verdad de qué IDs existen.

## Comandos usados para desplegar y verificar

```bash
terraform init      # descarga el provider archive agregado en este módulo
terraform plan
terraform apply

# Verificación manual (invocar la Lambda directo, sin pasar por Bedrock)
aws lambda invoke \
  --function-name agentinfra-create-ticket-dev \
  --payload '{"parameters":[{"name":"description","value":"no puedo entrar a mi cuenta"}]}' \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json

aws dynamodb scan --table-name agentinfra-tickets-dev
```

## Costo

- **DynamoDB (`PAY_PER_REQUEST`)**: mismo modo on-demand que la tabla de locking del Módulo 2 —
  para el volumen de pruebas de este proyecto, fracciones de centavo al mes.
- **Lambda**: dentro del free tier siempre gratuito (1M invocaciones/mes + 400,000 GB-segundos de
  cómputo), muy por encima de lo que este proyecto va a usar en pruebas manuales.

## Caso de uso (contexto para lo que viene)

Estas dos Lambdas son la mitad "tool" del agente de soporte descripto en el
[README](../README.md): cuando la Knowledge Base (Módulo 4) no alcanza para responder, el agente
recurre a `create_ticket`; para consultar un ticket ya creado, a `get_ticket_status`. Ver
[modules/agent-harness.md](agent-harness.md) para cómo estas Lambdas encajan como las "manos" del
harness del agente, y el Módulo 5 para el recurso que efectivamente las conecta.
