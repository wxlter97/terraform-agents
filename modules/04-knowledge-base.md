# Módulo 4 — Knowledge Base (RAG) con S3 Vectors

## Qué se construyó

- **`knowledge-base.tf`**:
  - `aws_s3_bucket.faqs` (+ cifrado, public access block): bucket con el contenido fuente de FAQ.
  - `aws_s3_object.faqs`: sube cada `.md` de `knowledge-base/faqs/` al bucket (`for_each` sobre
    `fileset(...)` — agregar un archivo nuevo ahí alcanza para que el próximo `apply` lo suba).
  - `aws_s3vectors_vector_bucket.kb` + `aws_s3vectors_index.kb`: el vector store. Un índice
    (`helpdesk-faqs`, 1024 dimensiones, distancia coseno) dentro de un vector bucket — un tipo de
    recurso propio del servicio S3 Vectors, no un bucket S3 "normal".
  - `aws_iam_role.bedrock_kb_role` + policy: rol de servicio de la Knowledge Base — distinto de
    `bedrock_agent_role` (Módulo 1), que es el rol del agente. Permisos: invocar el modelo de
    embeddings, leer el bucket de FAQ, y las cinco acciones `s3vectors:*` que documenta AWS para
    este caso (`PutVectors`, `GetVectors`, `DeleteVectors`, `QueryVectors`, `GetIndex`).
  - `aws_bedrockagent_knowledge_base.helpdesk`: `storage_configuration.type = "S3_VECTORS"`,
    `knowledge_base_configuration` con Titan Embeddings v2.
  - `aws_bedrockagent_data_source.faqs`: conecta el bucket de FAQ como fuente de datos S3.
- **`knowledge-base/faqs/*.md`**: tres FAQs iniciales del caso de uso helpdesk (reseteo de
  contraseña, cómo se crea un ticket, cómo consultar su estado).
- **`providers.tf`**: el provider `aws` subió de `~> 5.0` a `~> 6.0` — necesario porque los
  recursos `aws_s3vectors_*` no existían antes de la v6.24. Verificado con `terraform plan` antes
  de tocar nada más: la única diferencia de la guía de migración v5→v6 que afecta a este repo es
  un rename de atributo en `aws_s3_bucket` (`region` → `bucket_region`, que no usábamos en ningún
  lado), así que la subida no generó ningún diff inesperado sobre lo que ya estaba desplegado
  (Módulos 1-3).

Desplegado y verificado contra la cuenta real: `terraform apply` corrió sin `-target`, sin pasos
manuales — a diferencia de lo que se planeó originalmente (ver abajo).

## La historia real: por qué no es Aurora + pgvector

El plan original de este módulo era Aurora Serverless v2 + pgvector vía la RDS Data API (elegido
sobre OpenSearch Serverless por costo — ver la discusión al arrancar el módulo). Se abandonó a
mitad de implementación, con evidencia real contra la cuenta, no por lectura de documentación:

1. `terraform apply` sobre un `aws_rds_cluster` normal falló: `FreeTierRestrictionError: To use
   Aurora clusters with free plan accounts you need to set WithExpressConfiguration`. Esta cuenta
   de AWS es de tipo **"Free Plan"** (distinto del concepto de "servicio elegible para free
   tier" del resto del proyecto) — obliga a crear cualquier cluster Aurora con **Express
   Configuration**, un modo de creación rápida con sus propias restricciones.
2. El provider de Terraform (`hashicorp/aws`, incluso en su versión más reciente al momento de
   escribir esto) **no expone el parámetro `WithExpressConfiguration`** de la API de RDS — es
   una feature demasiado nueva. Hubo que crear el cluster a mano con `aws rds create-db-cluster
   --with-express-configuration` para poder seguir probando.
3. Express Configuration **no permite asociar el cluster a una VPC** (ni al crearlo ni después —
   se probó `modify-db-cluster` con subnet group y security group propios, y AWS lo rechaza
   explícitamente).
4. Sin VPC, **la RDS Data API no se puede habilitar** — se intentó con `modify-db-cluster
   --enable-http-endpoint` varias veces, la llamada "tiene éxito" (sin error) pero el flag nunca
   pasa a `true`. Confirmado como comportamiento esperado: la documentación de límites de la Data
   API lista la falta de asociación a VPC como la razón.
5. Bedrock Knowledge Bases con Aurora **solo funciona a través de la Data API** — no hay otra
   forma soportada de conectarse. Dead end confirmado, no solo teórico.

Se limpiaron los recursos generados en el intento (cluster Aurora creado a mano vía CLI, borrado
también a mano; `aws_db_subnet_group` y `aws_security_group` de Terraform, borrados con un
`apply` normal en cuanto se sacaron del `.tf`) y se pivotó a **S3 Vectors**, disponible en el
provider desde la v6.24 (requirió la subida de versión mencionada arriba). Sin cluster, sin VPC,
sin credenciales de base de datos — Bedrock accede vía IAM directo, igual que a S3 o DynamoDB.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **S3 Vectors** | Servicio de AWS para almacenar y consultar embeddings directamente sobre S3, sin levantar un cluster de base de datos ni un motor de búsqueda aparte. |
| **Vector bucket / vector index** | Recursos propios de S3 Vectors (`aws_s3vectors_vector_bucket`, `aws_s3vectors_index`), distintos de un bucket S3 normal — un vector bucket no guarda objetos, guarda vectores organizados en índices. |
| **Express Configuration (RDS)** | Modo de creación rápida de un cluster Aurora ("listo en segundos") que fija casi todos los parámetros automáticamente a cambio de perder configurabilidad — en particular, no se puede asociar a una VPC. |
| **RDS Data API** | Forma de ejecutar SQL contra Aurora por HTTPS (vía la API de AWS) en vez de una conexión TCP directa — requiere que el cluster tenga networking de VPC habilitado. |
| **Embedding model** | El modelo (acá, Titan Embeddings v2, 1024 dimensiones) que convierte texto en un vector numérico — tiene que coincidir la dimensión configurada en el índice de S3 Vectors con la que produce el modelo. |
| **Ingestion job** | El proceso por el cual Bedrock lee los documentos del data source (S3), los trocea, genera embeddings, y los guarda en el vector store. No hay recurso de Terraform para dispararlo (`StartIngestionJob` es una acción, no infraestructura) — se corre a mano. |
| **AWS account verification** | Un gate anti-abuso que AWS aplica a cuentas nuevas antes de habilitarles invocación de modelos de Bedrock (no simplemente *listarlos*) — normalmente se resuelve solo en menos de 2 horas. |

## Conceptos clave

- **Por qué "Free Plan" y "free tier" son cosas distintas**: "free tier" (usado en el resto de
  este proyecto) describe qué *servicios* son gratis dentro de ciertos límites de uso. "Free
  Plan" es un *tipo de cuenta* de AWS con restricciones propias sobre cómo se pueden crear
  ciertos recursos (acá, Aurora), independientes de si el uso resultante termina siendo gratis.
- **Por qué vale la pena documentar un dead end**: el tiempo perdido en Aurora no fue en vano
  para el aprendizaje — confirmar a mano que Express Configuration es incompatible con la Data
  API (en vez de asumirlo de la documentación) es la clase de diagnóstico real que hay que hacer
  en cualquier troubleshooting de infraestructura en producción.
- **Por qué S3 Vectors termina siendo más simple, no solo más barato**: no hay VPC, no hay
  cluster, no hay credenciales de base de datos que gestionar (nada de Secrets Manager en este
  módulo) — el rol IAM de la Knowledge Base accede directo, mismo patrón que ya se usa para S3 y
  DynamoDB en el resto del proyecto.
- **Por qué la subida de provider de v5 a v6 fue de bajo riesgo acá**: se verificó con
  `terraform plan` *antes* de tocar `knowledge-base.tf` que ningún recurso ya desplegado
  (Módulos 1-3) mostraba diffs inesperados — el único cambio de la guía de migración que aplica a
  este repo (`aws_s3_bucket.region` → `bucket_region`) no se usaba en ningún lado.

## Comandos usados para desplegar y verificar

```bash
terraform init -upgrade   # trae el provider aws v6.x
terraform plan            # verificar que Módulos 1-3 no muestran diffs inesperados
terraform apply

# Verificación manual
terraform output knowledge_base_id
aws bedrock-agent get-knowledge-base --knowledge-base-id <id>

# Disparar la ingesta (no hay recurso de Terraform para esto)
terraform output knowledge_base_data_source_id
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <knowledge_base_data_source_id>

# Seguir el estado del ingestion job
aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <knowledge_base_data_source_id>

# Una vez que el job termine (COMPLETE), probar una query
aws bedrock-agent-runtime retrieve \
  --knowledge-base-id <knowledge_base_id> \
  --retrieval-query '{"text": "cómo reseteo mi contraseña"}'
```

## La ingesta inicial quedó bloqueada, y se resolvió sola

El primer intento de `start-ingestion-job` devolvió un `ValidationException` — *"Your account is
currently being verified... normally takes less than 2 hours"* — un gate de AWS sobre cuentas
nuevas antes de habilitarles invocar modelos de Bedrock (no listar, invocar). No era un problema de
configuración: el rol IAM y los permisos estaban bien, era una verificación a nivel de cuenta.

Se resolvió sola, como decía el mensaje — se reintentó horas más tarde (durante el Módulo 6, al
verificar el agente end-to-end) y corrió limpio: `status: COMPLETE`, los 3 documentos de FAQ
indexados sin fallos. Una consulta real después de eso devolvió el contenido exacto de la FAQ —
ver [modules/06-api-gateway.md](06-api-gateway.md) para la prueba completa.

## Costo

- **S3 Vectors**: se paga por almacenamiento de vectores + por request de ingesta/query. Sin
  cluster corriendo entre sesiones, a diferencia de lo que hubiera costado Aurora incluso
  escalado a 0 ACU. Para el puñado de FAQs de este proyecto, centavos de dólar en el peor caso.
- **Bucket S3 de FAQs**: centavos al mes (mismo régimen que el bucket de state del Módulo 2).
- **Bedrock**: se cobra por token al generar embeddings durante la ingesta — volumen mínimo acá.

## Caso de uso (contexto para lo que viene)

Esta Knowledge Base es la mitad "RAG" del agente de soporte descripto en el
[README](../README.md): cuando el agente reciba una pregunta, primero va a intentar responderla
con estas FAQs antes de recurrir a las Lambdas `create_ticket` / `get_ticket_status` del
[Módulo 3](03-action-groups.md). Ver [agent-harness.md](agent-harness.md) para cómo esta pieza
encaja como la "memoria de largo plazo" del harness. El Módulo 5 es el que conecta ambas cosas
(action groups + esta Knowledge Base) al recurso del agente en sí.
