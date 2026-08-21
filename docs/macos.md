# Instalación y despliegue — macOS

Guía para instalar las herramientas necesarias y desplegar este proyecto desde cero en macOS.
Todos los comandos están pensados para Terminal (zsh/bash) con [Homebrew](https://brew.sh/)
instalado.

## 1. Prerrequisitos

- macOS con Homebrew instalado.
- Una cuenta de AWS dentro del free tier, con un usuario IAM que tenga credenciales de acceso
  programático (Access Key ID + Secret Access Key).

## 2. Instalar Terraform

```bash
brew install terraform
```

Verificá la instalación (este proyecto requiere Terraform >= 1.7.0):

```bash
terraform -version
```

## 3. Instalar AWS CLI

```bash
brew install awscli
```

Verificá:

```bash
aws --version
```

## 4. Configurar credenciales de AWS

```bash
aws configure
```

Vas a necesitar:

- `AWS Access Key ID`
- `AWS Secret Access Key`
- Región por defecto: `us-east-1` (Bedrock Agents solo está disponible en algunas regiones)
- Formato de salida: `json` (opcional)

## 5. Clonar el repositorio

```bash
git clone <url-del-repo>
cd terraform-agents
```

## 6. Desplegar la infraestructura

```bash
terraform init      # descarga los providers (ver .terraform.lock.hcl)
terraform plan       # revisá los recursos que se van a crear
terraform apply      # confirmá con "yes" para aplicar
```

Al terminar, Terraform muestra los outputs definidos en `outputs.tf` (ARNs de los roles IAM y el
`aws_account_id`).

## 7. Verificar el despliegue

```bash
terraform show
terraform output
```

También podés revisar los roles creados en la consola de AWS (IAM → Roles), buscando por el
prefijo `agentinfra-` (o el valor que le hayas dado a `project_name`).

## 8. Destruir los recursos

Para evitar cualquier costo, destruí los recursos cuando termines de probar:

```bash
terraform destroy
```

> **Nota de costos:** los recursos de este módulo (roles IAM) son gratis siempre. A partir del
> módulo en que se invoque un modelo de Bedrock, el uso deja de ser free tier y se cobra por
> token — revisá el `README.md` antes de aplicar módulos más avanzados.
