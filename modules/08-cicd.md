# Módulo 8 — CI/CD (GitHub Actions)

## Qué se construyó

- **`cicd.tf`**:
  - `aws_iam_openid_connect_provider.github_actions`: registra a GitHub Actions como proveedor de
    identidad federada de esta cuenta — sin esto, no hay forma de que un workflow "prueble" quién
    es ante AWS.
  - `aws_iam_role.github_actions_ci`: el rol que los workflows asumen. El trust policy usa
    `sts:AssumeRoleWithWebIdentity` (no `sts:AssumeRole`, ese es para roles asumidos por otro rol o
    usuario IAM) y restringe el claim `sub` del token de GitHub a
    `repo:wxlter97/terraform-agents:*` — cualquier branch/PR/workflow de este repo puntual, ningún
    otro repo ni cuenta.
  - `aws_iam_role_policy.github_actions_ci_policy`: permisos amplios por servicio (no
    least-privilege — ver más abajo el porqué).
- **`.github/workflows/terraform-plan.yml`**: en cada PR contra `master` que toque `.tf`,
  `lambda/`, o `knowledge-base/`, corre `fmt -check` → `init` → `validate` → `plan`, y comenta el
  resultado en el PR (actualiza el mismo comentario en pushes sucesivos, no acumula uno nuevo cada
  vez).
- **`.github/workflows/terraform-apply.yml`**: **solo** `workflow_dispatch` (botón manual en la
  pestaña Actions) — nunca se dispara automático al mergear a `master`. Además valida que el ref
  sea `refs/heads/master` antes de aplicar, para que no se pueda correr por error desde un branch
  con cambios sin revisar.

## OIDC en vez de Access Keys — por qué

La alternativa más simple (y la que muchos tutoriales usan) es generar un Access Key/Secret Key
para un usuario IAM y guardarlos como secrets de GitHub. Se prefirió OIDC acá por lo mismo que el
resto del proyecto evita credenciales estáticas en todos lados (mismo patrón que "todo vía IAM
roles, nunca usuarios/API keys" que ya venían los módulos anteriores): no hay ningún secreto de
larga vida que filtrar, rotar, ni revocar — el token que GitHub le pasa a AWS en cada corrida es
efímero y se emite recién en el momento, firmado por GitHub, verificado por AWS contra el
proveedor OIDC registrado en `cicd.tf`.

## Permisos amplios: una simplificación documentada, no un descuido

`github_actions_ci_policy` da acceso amplio (`iam:*`, `s3:*`, `dynamodb:*`, `lambda:*`,
`bedrock:*`, `bedrock-agentcore:*`, `apigateway:*`, `logs:*`, `cloudwatch:*`, `sns:*`,
`budgets:*`, todos con `Resource = "*"`) en vez de una policy realmente acotada. Es una decisión
consciente, no un olvido:

- Este proyecto termina tocando **11 servicios de AWS distintos** entre los ocho módulos. Escribir
  una policy least-privilege de verdad — con el ARN exacto de cada tabla, bucket, función, rol,
  gateway, harness, log group, tópico, alarm y budget que Terraform puede llegar a crear/modificar
  — es en sí mismo un proyecto de scoping considerable, y un permiso faltante rompe el CI en el
  peor momento (a mitad de un `apply`) en vez de fallar rápido y claro.
- `iam:*` en particular es difícil de acotar bien acá: Terraform gestiona roles y policies nuevos
  en casi todos los módulos (incluido este mismo rol de CI), así que cualquier intento de
  restringir "solo estos roles puntuales" se vuelve frágil cada vez que se agrega un módulo nuevo.
- Mismo patrón que la nota de seguridad del Módulo 6 (`POST /chat` sin auth): se documenta la
  simplificación en vez de fingir que no existe. Si este proyecto se llevara a un contexto real
  (no de aprendizaje), lo primero que habría que tightening es esto — separar por lo menos una
  policy de solo-lectura para el job de `plan` (que no necesita poder escribir nada) de una de
  lectura-escritura para `apply`.

## Configuración manual necesaria (una sola vez)

El rol IAM no sirve de nada si el workflow no sabe su ARN. Se hizo con `gh variable set` en vez de
dejarlo como paso manual, ya que `gh` ya estaba autenticado con los scopes necesarios:

```bash
terraform output -raw github_actions_ci_role_arn
gh variable set AWS_CI_ROLE_ARN --body "<el ARN de arriba>" --repo wxlter97/terraform-agents
```

Si se recrea este proyecto en otra cuenta/repo, este paso hay que repetirlo — Terraform no puede
configurar variables de repositorio de GitHub por sí solo (son parte de la config de GitHub, no
de AWS).

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **OIDC (OpenID Connect) federation** | Mecanismo por el cual un proveedor externo (acá, GitHub Actions) puede probar su identidad ante AWS con un token firmado y de corta duración, sin que AWS tenga que confiar en un secreto compartido de antemano. |
| **`sts:AssumeRoleWithWebIdentity`** | La acción de STS específica para asumir un rol usando un token de identidad web (OIDC/JWT) en vez de credenciales IAM existentes (`sts:AssumeRole`) o un usuario federado de SAML. |
| **Claim `sub` (subject)** | Campo del token JWT que GitHub Actions emite, con el formato `repo:OWNER/REPO:ref:refs/heads/BRANCH` (push) o `repo:OWNER/REPO:pull_request` (PR) — es lo que la trust policy compara para decidir si confía en ese token puntual. |
| **`workflow_dispatch`** | Trigger de GitHub Actions que solo se dispara manualmente (botón "Run workflow" en la UI, o vía API/`gh workflow run`) — nunca automático por un evento de git. |
| **Repository variable** (`vars` en GitHub Actions) | Configuración de repo no sensible (a diferencia de un *secret*) — acá, el ARN del rol, que no es secreto (conocerlo no alcanza para asumir el rol sin pasar también por la verificación OIDC). |

## Conceptos clave

- **Por qué `apply` no se dispara solo al mergear a `master`**: la revisión real ya pasó — el plan
  quedó comentado en el PR antes del merge — pero aplicar automáticamente igual sería "ejecutar
  infraestructura real sin que una persona decida conscientemente el momento". El
  `workflow_dispatch` fuerza ese click deliberado.
- **Por qué el guard de branch en `apply` y no solo confiar en que nadie lo dispare mal**: GitHub
  permite elegir *cualquier* branch al correr un `workflow_dispatch` manualmente desde la UI — sin
  el chequeo `github.ref != 'refs/heads/master'`, sería posible (por error) aplicar el código de un
  branch con cambios todavía no mergeados/revisados.
- **Por qué el comentario de plan se actualiza en vez de acumularse**: con `paths` filtrando a
  cambios relevantes, un PR que toca varios `.tf` en pushes sucesivos generaría un comentario nuevo
  por cada push si no se buscara primero uno existente con el marker `<!-- terraform-plan -->`.

## Comandos usados para desplegar y verificar

```bash
terraform init
terraform plan
terraform apply

terraform output -raw github_actions_ci_role_arn
gh variable set AWS_CI_ROLE_ARN --body "<arn>" --repo wxlter97/terraform-agents
gh variable list --repo wxlter97/terraform-agents

# Ver el rol y su trust policy
aws iam get-role --role-name agentinfra-github-actions-ci-dev
```

## Costo

- **IAM (rol, policy, OIDC provider)**: gratis siempre, como el resto del proyecto.
- **GitHub Actions**: gratis para repos públicos (este lo es) — minutos ilimitados en runners
  estándar de Linux.

## Caso de uso (contexto)

Con este módulo, el ciclo completo del proyecto queda cerrado: cambios de infraestructura pasan
por PR con plan visible antes de mergear, y el `apply` real a la cuenta de AWS queda como un paso
deliberado y separado — el mismo flujo que se usó a mano durante toda la construcción de los
módulos 1-7, ahora reproducible sin depender de que alguien tenga el AWS CLI configurado en su
máquina.
