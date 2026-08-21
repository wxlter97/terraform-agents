# Módulo 2 — Backend remoto (S3 + DynamoDB)

## Qué se construyó

- **`backend.tf`** — recursos de bootstrap para el backend remoto:
  - `aws_s3_bucket.tfstate`: bucket donde va a vivir `terraform.tfstate`. Se nombra
    `${project_name}-tfstate-<account_id>` porque los nombres de bucket S3 son únicos a nivel
    global (no alcanza con que sean únicos dentro de la cuenta), y `lifecycle.prevent_destroy`
    evita borrarlo por accidente con un `terraform destroy`.
  - `aws_s3_bucket_versioning.tfstate`: versionado activado — si el state se corrompe o se
    sobreescribe mal, se puede recuperar una versión anterior del objeto.
  - `aws_s3_bucket_server_side_encryption_configuration.tfstate`: cifrado en reposo (AES256).
  - `aws_s3_bucket_public_access_block.tfstate`: bloquea cualquier forma de acceso público al
    bucket (el state puede contener secretos/ARNs sensibles).
  - `aws_dynamodb_table.tfstate_lock`: tabla de locking, `billing_mode = "PAY_PER_REQUEST"` con
    clave de partición `LockID` (nombre fijo que espera Terraform).
- **`outputs.tf`** — se agregaron `tfstate_bucket_name` y `tfstate_lock_table_name` para poder
  copiar esos valores al bloque `backend "s3"`.
- **`providers.tf`** — el bloque `backend "s3"` queda comentado, listo para descomentar y
  completar con el nombre real del bucket una vez que existe.
- **`.gitignore`** — se agregó `*.tfstate` / `*.tfstate.*` (antes solo ignoraba `.terraform/`;
  `terraform.tfstate` y su `.backup` habían quedado sin trackear pero sin ignorar).

## El problema del huevo y la gallina

El bloque `backend` de Terraform **no acepta interpolación** (no puede usar `var.*` ni
referencias a recursos) porque Terraform necesita saber dónde está el state *antes* de evaluar
cualquier otra cosa de la configuración. Por eso el flujo de este módulo es en dos pasos:

1. Con el backend `local` todavía activo, `terraform apply` crea el bucket y la tabla
   (`backend.tf`). En este punto el state de *estos mismos recursos* sigue guardado en el
   `terraform.tfstate` local.
2. Se copia el nombre real del bucket (`terraform output tfstate_bucket_name`) al bloque
   `backend "s3"` de `providers.tf`, se descomenta, y se corre `terraform init -migrate-state`.
   Terraform detecta el cambio de backend y ofrece copiar el contenido del state local al bucket
   S3 recién creado — a partir de ahí el `terraform.tfstate` local ya no se usa (se puede borrar).

Comandos completos:

```bash
# Paso 1: crear bucket + tabla con backend local
terraform init
terraform plan
terraform apply

# Ver el nombre real del bucket para copiarlo al bloque backend "s3"
terraform output tfstate_bucket_name
terraform output tfstate_lock_table_name

# Paso 2: editar providers.tf (descomentar backend "s3", pegar el nombre del bucket)
# y migrar el state
terraform init -migrate-state
# Terraform pregunta: "Do you want to copy existing state to the new backend?" → yes

# Verificar que no hay drift después de migrar
terraform plan   # debería decir "No changes"
```

## Terminología nueva

| Término | Qué significa acá |
|---|---|
| **Backend remoto** | El state deja de vivir como archivo local y pasa a un almacenamiento compartido (S3), accesible desde cualquier máquina/CI. |
| **State locking** | Mecanismo para evitar que dos `terraform apply` corran en simultáneo sobre el mismo state y lo corrompan. La tabla DynamoDB con clave `LockID` es lo que usa el backend `s3` para esto. |
| **`terraform init -migrate-state`** | Comando que corre Terraform cuando cambia la configuración del `backend` — ofrece copiar el state existente del backend viejo al nuevo. |
| **Bootstrap problem** (huevo y gallina) | Necesitás recursos gestionados por Terraform (bucket, tabla) para poder usar el backend remoto, pero para crearlos con Terraform necesitás *algún* backend ya funcionando — se resuelve creándolos primero con backend local. |
| **Versionado de bucket S3** | Guarda cada versión de cada objeto en vez de sobreescribirla. Aplicado al state, permite recuperar una versión previa si algo lo corrompe. |
| **`prevent_destroy`** | Argumento de `lifecycle` que hace fallar el plan/apply si ese recurso sería destruido — protección contra borrar por error algo crítico (acá, el bucket que guarda el state de todo el proyecto). |
| **`billing_mode = "PAY_PER_REQUEST"`** | Modo *on-demand* de DynamoDB: se paga por request en vez de aprovisionar capacidad fija (RCU/WCU). Evita tener que estimar tráfico para una tabla que solo se usa como lock. |

## Conceptos clave

- **Por qué molesta el state local en equipo**: si el `terraform.tfstate` vive en el disco de una
  sola persona, nadie más puede aplicar cambios de forma segura (no hay una fuente de verdad
  compartida ni protección contra dos applies simultáneos). El backend remoto resuelve ambos
  problemas.
- **Por qué el bucket necesita el account id en el nombre**: los nombres de bucket S3 compiten en
  un namespace global (todas las cuentas de AWS), no solo dentro de la cuenta propia.
- **Por qué proteger el bucket de state con `prevent_destroy`**: perder el state no borra la
  infraestructura real en AWS, pero hace que Terraform "pierda la memoria" de qué gestiona — a
  partir de ahí, todo cambio requiere reconciliar manualmente o reimportar recursos.

## Costo

- **S3**: el bucket entra en el free tier siempre gratuito (5GB) — un `terraform.tfstate` de este
  proyecto pesa unos pocos KB.
- **DynamoDB on-demand**: a diferencia del modo *provisioned* (25 RCU/25 WCU siempre gratis), el
  modo `PAY_PER_REQUEST` se cobra por request desde la primera unidad. Para una tabla de locks que
  solo recibe un puñado de operaciones por cada `terraform plan`/`apply`, el costo real es
  fracciones de centavo al mes — en la práctica, gratis.

## Limpieza (si se quiere destruir todo)

`aws_s3_bucket.tfstate` tiene `prevent_destroy = true`, así que un `terraform destroy` directo
va a fallar en ese recurso a propósito. Para destruirlo de verdad:

1. Volver a mover el backend a `local` (`terraform init -migrate-state`, esta vez de `s3` hacia
   `local`) para no depender del bucket que se está por borrar.
2. Sacar el bloque `lifecycle { prevent_destroy = true }` de `backend.tf`.
3. Vaciar el bucket (incluidas las versiones, por el versionado) y recién ahí `terraform destroy`.

## Caso de uso (contexto para lo que viene)

Este módulo es infraestructura de soporte para el proyecto en sí (dónde vive el state), no del
agente de helpdesk. No cambia nada del caso de uso descripto en el [README](../README.md); lo
que sigue (módulo 3, Lambdas `create_ticket`/`get_ticket_status`) ya se apoya en un backend
remoto para poder trabajar con seguridad de que el state no se pisa entre corridas.
