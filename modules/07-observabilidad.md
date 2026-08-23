# Módulo 7 — Observabilidad

## Qué se construyó

- **`observability.tf`**:
  - `aws_cloudwatch_log_group` × 5: uno por cada Lambda (`create_ticket`, `get_ticket_status`,
    `query_faqs`, `chat_proxy`) y uno para el runtime del harness. Todos con
    `retention_in_days = 14` — el default de Lambda/AgentCore es "never expire", que en un
    proyecto que se prende y apaga seguido termina acumulando logs (y costo de storage) sin
    necesidad.
  - `aws_sns_topic.alerts` + `aws_sns_topic_subscription` (email): destino común de todas las
    alarms de este módulo.
  - `aws_cloudwatch_metric_alarm` × 10: errores y throttles por cada una de las 4 Lambdas (8), más
    5xx y latencia p90 del endpoint `/chat` (2).
  - `aws_budgets_budget.monthly`: budget de $5/mes filtrado por el tag `Project` (que
    `default_tags` ya pone en todo recurso), con notificaciones a los 80% de gasto real y 100% de
    gasto proyectado.

## El problema del huevo y la gallina (de nuevo) — pero al revés que el Módulo 2

Los log groups de las Lambdas y del harness **ya existían** antes de este módulo — se crean solos
la primera vez que algo se invoca, con retención "never expire". Escribir
`aws_cloudwatch_log_group` con esos mismos nombres y correr `apply` directo hubiera fallado
(`ResourceAlreadyExistsException`): a diferencia del Módulo 2 (donde el recurso no existía y había
que crearlo con un backend viejo primero), acá el recurso ya estaba, solo que fuera del control de
Terraform. Se resolvió con `terraform import` antes del primer `apply` de este módulo — cuatro
imports (tres Lambdas + el runtime del harness; `get_ticket_status` nunca se había invocado
directo, así que su log group no existía y se creó normal):

```bash
terraform import 'aws_cloudwatch_log_group.lambda["create_ticket"]' /aws/lambda/agentinfra-create-ticket-dev
terraform import 'aws_cloudwatch_log_group.lambda["query_faqs"]' /aws/lambda/agentinfra-query-faqs-dev
terraform import 'aws_cloudwatch_log_group.lambda["chat_proxy"]' /aws/lambda/agentinfra-chat-proxy-dev
terraform import 'aws_cloudwatch_log_group.harness_runtime' /aws/bedrock-agentcore/runtimes/harness_agentinfrahelpdeskdev-ZuynqWGzYQ-DEFAULT
```

Después del import, `terraform plan` mostró un `update in-place` esperable en cada uno (pasar de
sin retención a 14 días) — no un `destroy`/`create`, que es la señal de que el import salió bien.

## Por qué la métrica de latencia no es la del harness

Invocar el harness de verdad (Módulo 6) dejó ver que AgentCore publica métricas propias en el
namespace `bedrock-agentcore`, con nombres estilo OpenTelemetry:
`gen_ai.client.operation.duration`, `strands.tool.duration`, `strands.event_loop.cycle_duration`,
`http.server.duration`, entre otras (el prefijo `strands.*` sugiere que el runtime administrado
del harness corre sobre el framework Strands Agents por dentro). Son genuinamente más precisas que
la latencia de API Gateway para medir "qué tan rápido responde el agente" — pero
`gen_ai.client.operation.duration` en particular aparece con **combinaciones de dimensiones
variables** (`error.type` presente o ausente según si esa invocación falló), así que una alarm de
CloudWatch normal (que necesita un set de dimensiones fijo) no la puede usar directo — haría falta
una `metric_query` con expresión `SEARCH(...)` para agregar across dimensiones, fuera de alcance
para una alarm "básica". Se usó en su lugar `AWS/ApiGateway Latency` (p90), que mide el tiempo
total de punta a punta que ve el caller — menos preciso sobre *dónde* está la lentitud, pero simple,
estable, y en la práctica lo que le importa a quien llama al endpoint.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **Log retention** | Cuántos días CloudWatch guarda las entradas de un log group antes de borrarlas automáticamente — sin configurar, Lambda/AgentCore usan "never expire". |
| **`treat_missing_data`** | Qué hace una alarm cuando no hay datapoints en el período evaluado — acá `notBreaching`, para que la ausencia de invocaciones (normal en un proyecto de aprendizaje) no dispare una alarm de error. |
| **`extended_statistic` (percentiles)** | Estadística sobre la distribución de valores de una métrica (ej. `p90`) en vez de un agregado simple (`Sum`, `Average`) — usado acá para la alarm de latencia, más representativo que un promedio cuando hay outliers. |
| **AWS Budget** | Recurso separado de CloudWatch (`aws_budgets_budget`) que trackea gasto real/proyectado de la cuenta (o de un subconjunto filtrado por tag) contra un límite, con notificaciones propias — no usa SNS, tiene su propio mecanismo de email. |
| **`cost_filter` (TagKeyValue)** | Cómo se le dice a un Budget que solo cuente el gasto de recursos con un tag puntual, en vez de toda la cuenta. |

## Conceptos clave

- **Por qué un budget y no solo alarms de CloudWatch**: las alarms de este módulo detectan
  *síntomas* (errores, latencia) — el budget es la única red contra la causa raíz del riesgo que
  quedó documentado en el Módulo 6 (endpoint público sin auth ni throttle): gasto que crece sin
  que haya necesariamente un error técnico que lo señale.
- **Por qué el budget filtra por tag y no es de toda la cuenta**: esta cuenta se usa solo para este
  proyecto en la práctica, pero filtrar por tag es la práctica correcta igual — si en el futuro se
  usa la misma cuenta para otra cosa, el budget de este proyecto no se ve afectado por gasto ajeno.
- **Por qué `ok_actions` solo en la alarm de errores de Lambda**: es la única alarm de este módulo
  donde "volvió a la normalidad" es una noticia que vale la pena — para throttles/5xx/latencia,
  alcanza con la notificación de que empezó el problema.

## Comandos usados para desplegar y verificar

```bash
# Imports (una sola vez, antes del primer apply de este módulo)
terraform import 'aws_cloudwatch_log_group.lambda["create_ticket"]' /aws/lambda/agentinfra-create-ticket-dev
# ...(ver arriba)

terraform plan
terraform apply

# Confirmar la suscripción de SNS (llega un mail, hay que clickear el link)
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw... )  # ver ARN en la consola si hace falta

# Ver las alarms
aws cloudwatch describe-alarms --alarm-name-prefix agentinfra --query "MetricAlarms[].{name:AlarmName,state:StateValue}" --output table
```

## Costo

- **CloudWatch Logs**: la retención de 14 días evita acumulación indefinida — para el volumen de
  este proyecto, centavos de dólar al mes en el peor caso.
- **CloudWatch Alarms**: las primeras 10 alarms por cuenta son gratis siempre (free tier
  siempre-gratuito) — este módulo usa exactamente 10, así que queda en $0 mientras no se agreguen
  más.
- **SNS**: 1M notificaciones/mes gratis en el free tier de 12 meses — el volumen de este proyecto
  no se acerca.
- **AWS Budgets**: las primeras dos acciones de budget por mes son gratis; el resto de la feature
  (tracking + notificaciones simples) no tiene costo aparte.

## Caso de uso (contexto)

Este módulo no le agrega nada al comportamiento del agente de soporte en sí — es la capa que
avisa cuando algo se rompe (errores, latencia) o cuando el proyecto empieza a costar más de lo
esperado, en vez de descubrirlo por accidente revisando la cuenta de AWS.
