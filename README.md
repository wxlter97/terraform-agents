# agent-infra-terraform

Proyecto de práctica: infraestructura como código para agentes de IA en AWS,
usando Terraform y priorizando servicios dentro del free tier.

## Por qué este enfoque

- Terraform como herramienta única, independiente del proveedor.
- AWS porque es el más reconocido comercialmente para certificación y CV.
- El foco de contenido es agentes (Bedrock Agents), que es donde está yendo
  la demanda de arquitectura/DevOps en los próximos 1-2 años.

## Prerrequisitos (en tu máquina, no en este sandbox)

```bash
# Terraform
brew install terraform    # o el gestor de paquetes que uses

# AWS CLI + credenciales de una cuenta free tier
aws configure
```

## Nota sobre costos

- IAM, Lambda (1M invocaciones/mes), DynamoDB (25GB), S3 (5GB) → dentro del
  free tier siempre gratuito de AWS.
- **Bedrock NO está en el free tier**: se cobra por token invocado. Usando
  modelos económicos (ej. Claude Haiku) y probando con moderación, el costo
  de todo este roadmap debería mantenerse en centavos de dólar. Te aviso en
  cada módulo qué recurso sí genera costo.

## Caso de uso

El agente que se va a construir es un **asistente de soporte técnico / helpdesk**:

- Un usuario le hace una pregunta en lenguaje natural (ej. "¿cómo reseteo mi contraseña?").
- El agente primero busca la respuesta en una **Knowledge Base** de FAQs/documentación propia
  subida a S3 (módulo 4, RAG) y responde si encuentra la info.
- Si no puede resolverlo con la documentación, usa una **tool** (Lambda, módulo 3) para crear un
  ticket en DynamoDB, y otra para consultar el estado de un ticket existente.
- El conjunto se expone como un endpoint HTTP (módulo 6) al que cualquier front-end o script
  puede llamar.

Este caso de uso guía las decisiones de diseño de los módulos 3 y 4: las Lambdas de action group
serán `create_ticket` y `get_ticket_status` sobre una tabla DynamoDB, y la Knowledge Base
contendrá documentos de FAQ (texto plano o Markdown) subidos a S3.

## Módulo 1 — Fundamentos

- Provider AWS + backend local.
- Rol IAM que Bedrock asumirá para ejecutar el agente.
- Rol IAM de ejecución para las Lambdas que serán las "herramientas" del agente.

```bash
terraform init
terraform plan
terraform apply
```

## Módulo 2 — Backend remoto

- Bucket S3 (versionado, cifrado, sin acceso público) para guardar el `terraform.tfstate`.
- Tabla DynamoDB (`PAY_PER_REQUEST`) para el locking del state.
- Migración del backend `local` al backend `s3`.

Bootstrap en dos pasos (el bloque `backend` de Terraform no acepta variables, así que el nombre
del bucket hay que copiarlo a mano una vez creado):

```bash
# 1. Crear el bucket y la tabla con el backend local todavía activo
terraform init
terraform apply

# 2. Copiar el nombre real del bucket al bloque backend "s3" comentado en
#    providers.tf y migrar el state existente
terraform output tfstate_bucket_name
terraform init -migrate-state
```

Detalle completo en [modules/02-backend-remoto.md](modules/02-backend-remoto.md).

## Módulo 3 — Action groups

- Tabla DynamoDB de tickets + policy de acceso para `lambda_exec_role` (Módulo 1).
- Lambdas `create_ticket` y `get_ticket_status`, empaquetadas con el provider `archive`.
- Quedan desplegadas pero inertes hasta el Módulo 5 (falta el recurso del agente y el permiso de
  invocación resource-based del lado de la Lambda).

```bash
terraform init
terraform plan
terraform apply
```

Detalle completo en [modules/03-action-groups.md](modules/03-action-groups.md).

## Módulo 4 (este) — Knowledge Base (RAG)

- Bucket S3 con contenido de FAQ (`knowledge-base/faqs/*.md`), subido vía Terraform.
- Vector store en **S3 Vectors** — no Aurora/pgvector, el plan original: esa cuenta de AWS es de
  tipo "Free Plan" y eso hace que Aurora sea incompatible con la RDS Data API que Bedrock necesita
  para conectarse. Ver [modules/04-knowledge-base.md](modules/04-knowledge-base.md) para la
  historia completa del descarte.
- `aws_bedrockagent_knowledge_base` + `aws_bedrockagent_data_source` sobre ese vector store.
- Requiere el provider AWS `~> 6.0` (subido desde `~> 5.0` para los recursos `aws_s3vectors_*`).

```bash
terraform init -upgrade
terraform plan
terraform apply

# Disparar la ingesta inicial (no hay recurso de Terraform para esto)
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw knowledge_base_data_source_id)
```

Detalle completo en [modules/04-knowledge-base.md](modules/04-knowledge-base.md).

## Roadmap de módulos siguientes

5. Bedrock Agent + Agent Alias, conectando los action groups del módulo 3 y la Knowledge Base del
   módulo 4.
6. API Gateway + Lambda proxy para invocar el agente desde afuera.
7. Observabilidad: CloudWatch logs y alarms.
8. CI/CD: GitHub Actions con `terraform plan`/`apply` en pull requests.
