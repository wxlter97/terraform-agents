# Módulo 1 — Fundamentos

## Qué se construyó

Toda la infraestructura de este módulo vive en el root module (no hay submódulos todavía):

- **`providers.tf`** — configuración de Terraform (versión mínima, provider AWS `~> 5.0`) y
  backend `local` (el state se guarda como archivo en el disco).
- **`variables.tf`** — `aws_region` (default `us-east-1`), `project_name` (default
  `agentinfra`), `environment` (default `dev`).
- **`iam.tf`** — dos roles IAM y sus políticas:
  - `aws_iam_role.bedrock_agent_role`: el rol que Bedrock asume para invocar el modelo
    fundacional en nombre del agente.
  - `aws_iam_role_policy.bedrock_agent_policy`: permite `bedrock:InvokeModel` sobre cualquier
    foundation model.
  - `aws_iam_role.lambda_exec_role`: rol de ejecución para las futuras Lambdas de action groups
    (módulo 3) — se creó ya en este módulo para no tener que reordenar recursos después.
  - `aws_iam_role_policy_attachment.lambda_basic`: adjunta la policy administrada
    `AWSLambdaBasicExecutionRole` (permisos mínimos de logging a CloudWatch).
  - `aws_iam_role_policy.bedrock_invoke_lambda`: permite que `bedrock_agent_role` invoque
    Lambdas cuyo nombre empiece con `${project_name}-`.
- **`outputs.tf`** — expone los ARNs de ambos roles y el `aws_account_id` de la cuenta donde se
  desplegó.

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **IAM Role** | Identidad de AWS sin credenciales fijas, pensada para que la "asuma" un servicio o usuario temporalmente (a diferencia de un IAM User). |
| **Trust policy** (`assume_role_policy`) | Define **quién** puede asumir el rol. En `bedrock_agent_role`, el `Principal` es el servicio `bedrock.amazonaws.com`. |
| **Principal** | La entidad autorizada por la trust policy — puede ser un servicio de AWS, una cuenta, o un usuario. |
| **`sts:AssumeRole`** | La acción que efectivamente "presta" el rol a quien lo asume, vía AWS Security Token Service. |
| **Policy (inline vs. administrada/managed)** | Una policy *inline* (`aws_iam_role_policy`) vive pegada a un solo rol; una *administrada* (`aws_iam_role_policy_attachment`, ej. `AWSLambdaBasicExecutionRole`) es reutilizable entre roles y la mantiene AWS. |
| **ARN** (Amazon Resource Name) | Identificador único de un recurso de AWS, ej. `arn:aws:iam::123456789012:role/agentinfra-bedrock-agent-role-dev`. |
| **Data source** (`data "aws_caller_identity" "current"`) | Bloque de Terraform que *lee* información existente en AWS (acá, la cuenta actual) en vez de crear un recurso nuevo. |
| **Confused deputy problem** | El riesgo de que un servicio de AWS sea engañado para actuar en nombre de la cuenta equivocada. Se mitiga con la condición `aws:SourceAccount` en la trust policy, que restringe quién puede pedirle a Bedrock que asuma el rol. |
| **Backend (de Terraform)** | Dónde y cómo se guarda el `state`. Acá es `local` (archivo `terraform.tfstate` en el repo, gitignoreado). |
| **State** | El registro que mantiene Terraform de qué recursos reales corresponden a qué bloques de configuración. |
| **Lock file** (`.terraform.lock.hcl`) | Fija las versiones exactas de los providers descargados, para builds reproducibles. Se versiona en git (a diferencia del state). |
| **`default_tags`** | Tags que el provider aplica automáticamente a *todos* los recursos que soporten tagging — evita repetirlos recurso por recurso. |

## Conceptos clave

- **Por qué el agente necesita su propio rol**: Bedrock no tiene permisos por sí mismo para
  invocar un modelo o una Lambda — necesita asumir un rol con esos permisos explícitos. Esto es
  el patrón estándar de IAM en AWS: *nada* tiene permisos por defecto.
- **Por qué las Lambdas tienen un rol separado del rol del agente**: son dos identidades
  distintas en tiempo de ejecución — el agente (como llamador) y la Lambda (como ejecutora) cada
  una necesita sus propios permisos, siguiendo el principio de mínimo privilegio.
- **"Dejar el terreno listo" para módulos futuros**: `lambda_exec_role` no se usa todavía (no
  hay ninguna Lambda desplegada), pero se creó ahora para no reestructurar el código en el
  módulo 3 — un patrón común en IaC cuando se sabe de antemano qué viene después.
- **Costo**: todo lo de este módulo (roles y policies IAM) es gratis siempre en AWS, sin límite
  de uso — a diferencia de Bedrock (se cobra por token) que entra recién en módulos posteriores.

## Comandos usados para desplegar y verificar

```bash
terraform init
terraform plan
terraform apply

# Verificación manual
terraform output
aws iam get-role --role-name agentinfra-bedrock-agent-role-dev

# Limpieza
terraform destroy
```

## Caso de uso (contexto para lo que viene)

Se definió que el agente final será un **asistente de soporte técnico/helpdesk** (ver
"Caso de uso" en [README.md](../README.md)). Este módulo no lo refleja todavía — es pura base de
permisos — pero condiciona el diseño de los módulos 3 (`create_ticket`, `get_ticket_status`) y 4
(Knowledge Base de FAQs).
