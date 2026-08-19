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

## Módulo 1 (este) — Fundamentos

- Provider AWS + backend local.
- Rol IAM que Bedrock asumirá para ejecutar el agente.
- Rol IAM de ejecución para las Lambdas que serán las "herramientas" del agente.

```bash
terraform init
terraform plan
terraform apply
```

## Roadmap de módulos siguientes

2. Backend remoto real: S3 + DynamoDB para state y locking (free tier).
3. Lambda action groups: funciones que el agente puede invocar como herramientas.
4. Knowledge Base: S3 + vector store para RAG del agente.
5. Bedrock Agent + Agent Alias, conectando los action groups del módulo 3.
6. API Gateway + Lambda proxy para invocar el agente desde afuera.
7. Observabilidad: CloudWatch logs y alarms.
8. CI/CD: GitHub Actions con `terraform plan`/`apply` en pull requests.
