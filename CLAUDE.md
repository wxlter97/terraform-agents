# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`agent-infra-terraform`: a learning project building AWS infrastructure-as-code for AI agents
(AWS Bedrock Agents) with Terraform, staying inside the AWS free tier wherever possible.
Documentation and comments in this repo are written in Spanish — match that when editing
existing files.

This is currently **Módulo 1** of a planned multi-module roadmap (see README.md). Only the IAM
foundation exists so far:
- `aws_iam_role.bedrock_agent_role` — role Bedrock assumes to invoke the foundation model.
- `aws_iam_role.lambda_exec_role` — execution role for future action-group Lambdas (Módulo 3),
  provisioned early so resources don't need reordering later.
- A policy on `bedrock_agent_role` grants it `lambda:InvokeFunction` on any function named
  `${var.project_name}-*`, anticipating the action-group Lambdas.

Planned next modules (do not build ahead of the current module unless asked): remote S3+DynamoDB
backend, Lambda action groups, a Knowledge Base (S3 + vector store) for RAG, the Bedrock Agent +
Agent Alias itself, an API Gateway proxy, CloudWatch observability, and GitHub Actions CI/CD.

**Concrete use case (guides módulos 3-4 onward, see README.md "Caso de uso"):** a support/helpdesk
agent. It answers user questions from a Knowledge Base of FAQs stored in S3 (RAG, módulo 4); when
that's not enough, it falls back to action-group Lambdas — `create_ticket` and
`get_ticket_status` — backed by DynamoDB (módulo 3). Keep new Lambdas/KB content aligned with this
scenario unless the user redirects it.

## Commands

Standard Terraform workflow, run from the repo root:

```bash
terraform init      # downloads providers per .terraform.lock.hcl
terraform plan
terraform apply
terraform fmt       # formats *.tf files — run before committing changes to .tf files
terraform validate  # checks config validity without touching AWS
```

There is no test suite, linter, or build step beyond Terraform's own `fmt`/`validate`. Applying
requires AWS credentials (`aws configure`) for a free-tier account; `providers.tf` targets
`us-east-1` by default via `var.aws_region`.

State is local (`backend "local"`, `providers.tf`) — `terraform.tfstate` is produced in the repo
root on apply and is gitignored along with `.terraform`.

## Learning log (`/modules`)

`modules/` holds **learning notes, not Terraform modules** (this project has no submodules — see
Architecture notes below). One file per roadmap step (`01-fundamentos.md`, `02-backend-remoto.md`,
…, matching the numbering in README.md), covering what was built, new terminology, and key
concepts. When a roadmap module is completed, add its `modules/NN-nombre.md` file (see
`modules/01-fundamentos.md` for the expected shape) and update the status table in
`modules/README.md`.

## Architecture notes

- Root-module-only layout: `providers.tf` (Terraform/provider/backend config), `variables.tf`
  (`aws_region`, `project_name`, `environment`), `iam.tf` (resources), `outputs.tf`. No
  submodules yet — everything lives in the root module.
- Resource naming convention: `${var.project_name}-<purpose>-${var.environment}` (see the IAM
  role names in `iam.tf`). Keep new resources consistent with this pattern.
- `default_tags` in `providers.tf` already stamps every resource with `Project`, `Environment`,
  `ManagedBy` — don't add those tags manually on individual resources.
- Bedrock is **not** free-tier (billed per token); IAM/Lambda/DynamoDB/S3 usage in this roadmap
  stays within AWS's always-free tier. When adding a resource that incurs cost, note it (the
  README calls this out per module in Spanish) so the pattern established there continues.
