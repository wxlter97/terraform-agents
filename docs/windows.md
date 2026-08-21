# Instalación y despliegue — Windows (WSL)

Guía para instalar las herramientas necesarias y desplegar este proyecto desde cero en Windows,
usando **WSL** (Windows Subsystem for Linux) con una distro Ubuntu/Debian. Todos los comandos de
esta guía están pensados para la terminal de WSL (bash) — no para PowerShell ni CMD.

## 0. Prerrequisitos de WSL

Si todavía no tenés WSL instalado, desde PowerShell (como administrador), **fuera** de WSL:

```powershell
wsl --install -d Ubuntu
```

Reiniciá si te lo pide y abrí la app "Ubuntu" para terminar de configurarla (usuario y contraseña
de Linux). De acá en adelante, todos los comandos se ejecutan **dentro de la terminal de WSL**.

También vas a necesitar una cuenta de AWS dentro del free tier, con un usuario IAM que tenga
credenciales de acceso programático (Access Key ID + Secret Access Key).

## 1. Actualizar paquetes

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Instalar Terraform

Este proyecto requiere Terraform >= 1.7.0. Instalalo desde el repositorio oficial de HashiCorp:

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install terraform
```

Verificá la instalación:

```bash
terraform -version
```

## 3. Instalar AWS CLI

```bash
sudo apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/
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

Trabajá dentro del filesystem de Linux (por ejemplo `~/proyectos`), no en `/mnt/c/...`: Git y
Terraform corren notablemente más rápido ahí y evitás problemas de permisos entre Windows y WSL.

```bash
mkdir -p ~/proyectos && cd ~/proyectos
git clone <url-del-repo>
cd terraform-agents
```

> Tip: si editás desde VS Code, instalá la extensión "WSL" y abrí la carpeta con `code .` desde
> la terminal de WSL, para que todo (terminal integrada, extensiones, etc.) corra dentro de Linux.

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
