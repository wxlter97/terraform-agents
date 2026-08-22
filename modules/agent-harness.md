# Concepto — Agent harness (arquitectura de orquestación del agente)

> Nota: a diferencia del resto de `modules/`, este archivo no corresponde a un paso numerado del
> roadmap — es una nota conceptual transversal, útil como preparación para el **Módulo 5**
> (Bedrock Agent + Agent Alias), donde estas piezas se declaran en Terraform por primera vez.

## Qué es un "harness"

Un **harness** ("arnés"/andamiaje) es la capa de software que rodea a un modelo fundacional (LLM)
y lo convierte en un *agente* capaz de actuar, no solo de responder texto. El modelo por sí solo
únicamente predice el siguiente token; todo lo demás — decidir qué herramienta llamar, mantener el
hilo de la conversación, armar el prompt en cada paso, interpretar el resultado de una tool y
decidir el siguiente paso — lo hace el harness.

En términos de responsabilidades, un harness típico resuelve:

1. **Bucle de razonamiento** (*reasoning/orchestration loop*): en cada turno, decide si el modelo
   tiene suficiente información para responder o si necesita invocar una herramienta / consultar
   una fuente de datos antes de continuar. Se repite hasta llegar a una respuesta final.
2. **Selección y ejecución de herramientas** (*tool use / function calling*): expone al modelo un
   catálogo de funciones disponibles (con nombre, descripción y esquema de parámetros), interpreta
   cuándo el modelo "pide" usar una, la ejecuta de verdad, y le devuelve el resultado.
3. **Estado de sesión** (*session state*): memoria de corto plazo entre turnos de una misma
   conversación (qué se preguntó antes, qué herramientas ya se llamaron, resultados intermedios).
4. **Instrucciones / prompt de sistema**: la definición de personalidad, objetivo y reglas de
   orquestación del agente (ej. "si no encontrás la respuesta en la base de conocimiento, creá un
   ticket").
5. **Observabilidad** (*trace*): registro de cada paso del razonamiento — qué tool se llamó, con
   qué argumentos, qué devolvió — para poder depurar por qué el agente actuó como actuó.

## Harness "manejado" vs. "hecho a mano"

- **Hecho a mano**: usando la API de un modelo directamente (ej. Anthropic Messages API con tool
  use), el bucle de razonamiento lo escribís vos — parseás la respuesta del modelo, ejecutás la
  tool si la pidió, le devolvés el resultado, repetís. El Claude Agent SDK es un ejemplo de
  herramienta que te da ese bucle ya armado para construir agentes con modelos de Anthropic.
- **Manejado (managed)**: el proveedor de nube corre el bucle por vos. **Esto es lo que hace AWS
  Bedrock Agents** — no se escribe código de orquestación; se *declara* de qué piezas dispone el
  agente (modelo, instrucciones, action groups, knowledge base) y Bedrock ejecuta internamente el
  ciclo preprocesamiento → orquestación → (RAG opcional) → postprocesamiento.

Este proyecto usa la variante manejada: el "harness" no se programa, se **configura vía IAM +
recursos de Bedrock**, que es exactamente lo que ya se viene construyendo módulo a módulo.

## Cómo se traduce al proyecto (mapeo de piezas)

| Componente del harness | Pieza equivalente acá | Estado |
|---|---|---|
| Modelo fundacional ("el cerebro") | `bedrock_agent_role` + policy `bedrock:InvokeModel` ([iam.tf](../iam.tf)) | ✅ Módulo 1 |
| Herramientas ("las manos") | Lambdas `create_ticket` / `get_ticket_status`, action group ([action-groups.tf](../action-groups.tf)) | ✅ Módulo 3 |
| Memoria de largo plazo / retrieval | Knowledge Base (S3 + vector store) | ⏳ Módulo 4 |
| Instrucciones + bucle de orquestación | `aws_bedrockagent_agent` (prompt de sistema, orquestación RAG-vs-tool) | ⏳ Módulo 5 |
| Versión estable invocable | Agent Alias (`aws_bedrockagent_agent_alias`) | ⏳ Módulo 5 |
| Estado de sesión | Sesión de invocación del agente (`InvokeAgent`, maneja Bedrock) | ⏳ Módulo 5/6 |
| Observabilidad del razonamiento | CloudWatch logs/traces del agente | ⏳ Módulo 7 |

Es decir: los Módulos 1 y 3 ya construyeron el "cerebro" y las "manos" del harness. Lo que falta
(Módulo 5) es el recurso que efectivamente las conecta y define *cómo* el modelo decide entre
responder con la Knowledge Base o llamar una Lambda — ese "cómo decide" es la orquestación del
harness, y en Bedrock Agents se configura, no se programa.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **Harness (agent harness)** | Capa de software (manejada o propia) que envuelve al LLM: bucle de razonamiento, ejecución de tools, estado de sesión y prompt de sistema. |
| **Reasoning loop / orchestration loop** | Ciclo "pensar → decidir si actuar → actuar → observar resultado → repetir" hasta llegar a una respuesta final. En Bedrock Agents es un patrón estilo *ReAct*. |
| **Tool use / function calling** | Mecanismo por el cual el modelo puede "pedir" ejecutar una función externa (acá, una Lambda de action group) en vez de responder directamente en texto. |
| **Action group** | Concepto de Bedrock: agrupa una o más funciones (Lambdas) que el agente puede invocar como herramientas, con su esquema de parámetros. |
| **Session state / session attributes** | Memoria de corto plazo que Bedrock mantiene durante una conversación con `InvokeAgent`, sin que el desarrollador tenga que persistirla manualmente. |
| **Trace** | Registro paso a paso de la orquestación (qué decidió el agente, qué tool llamó, qué devolvió) que Bedrock puede devolver para depuración/observabilidad. |
| **Agent Alias** | Puntero estable a una versión publicada del agente — permite actualizar el agente (nueva versión) sin romper a quien lo está invocando por el alias. |

## Por qué importa ahora

Los Módulos 1 y 3 se sintieron como "solo permisos e infraestructura suelta" porque, sin el
recurso del agente (Módulo 5), no hay todavía un harness real conectándolos — son piezas
preparadas de antemano (ver "dejar el terreno listo" en
[01-fundamentos.md](01-fundamentos.md)). Tener claro el concepto de harness ahora sirve para que,
al llegar al Módulo 5, las decisiones de diseño (qué van las instrucciones del agente, cómo se
referencia el action group, cómo se conecta la Knowledge Base) se entiendan como *configuración de
un harness manejado*, no como recursos aislados.

## Costo

Este archivo es puramente conceptual — no agrega recursos de Terraform ni costo.
