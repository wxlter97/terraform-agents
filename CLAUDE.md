# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`agent-infra-terraform`: a learning project building AWS infrastructure-as-code for AI agents
(AWS Bedrock Agents) with Terraform, staying inside the AWS free tier wherever possible.
Documentation and comments in this repo are written in Spanish — match that when editing
existing files.

This is currently **Módulo 4** of a planned multi-module roadmap (see README.md). Módulos 1-4 are
done and actually deployed (not just code-complete — this account's real state was checked with
`terraform state list` partway through, since earlier sessions had assumed "code exists" meant
"applied," which wasn't true for Módulo 3 until it was actually run):
- **Módulo 1 (IAM)** — `aws_iam_role.bedrock_agent_role` (role Bedrock assumes to invoke the
  foundation model) and `aws_iam_role.lambda_exec_role` (execution role for action-group
  Lambdas), plus a policy granting `bedrock_agent_role` `lambda:InvokeFunction` on any function
  named `${var.project_name}-*`.
- **Módulo 2 (remote backend)** — `backend.tf` bootstraps an S3 bucket (versioned, encrypted,
  `prevent_destroy`) and a DynamoDB lock table; `providers.tf`'s `backend "s3"` block is now the
  active backend (migrated from local).
- **Módulo 3 (action groups)** — `action-groups.tf` + `lambda/`: a `tickets` DynamoDB table and
  the `create_ticket` / `get_ticket_status` Lambdas, using `lambda_exec_role` from Módulo 1.
- **Módulo 4 (Knowledge Base / RAG)** — `knowledge-base.tf`: FAQ content in S3 +
  `aws_bedrockagent_knowledge_base` backed by **S3 Vectors** (not Aurora/pgvector — that path is
  a confirmed dead end on this account, see below). Initial ingestion is pending an AWS
  account-verification gate, unrelated to the Terraform config — see
  [modules/04-knowledge-base.md](modules/04-knowledge-base.md).

**This AWS account is a "Free Plan" account type** (distinct from "free-tier eligible services") —
it forces Aurora clusters into Express Configuration, which cannot attach a VPC or enable the RDS
Data API, which Bedrock's Aurora-as-KB integration requires. Confirmed by hands-on testing, not
just docs. Keep this in mind if a future module reaches for another RDS/Aurora-backed resource —
check for Free Plan restrictions early rather than assuming standard AWS behavior.

Planned next modules (do not build ahead of the current module unless asked): the Bedrock Agent +
Agent Alias itself (which actually wires the action groups and KB together — see
[modules/agent-harness.md](modules/agent-harness.md) for the orchestration concepts behind it), an
API Gateway proxy, CloudWatch observability, and GitHub Actions CI/CD.

**Concrete use case (guides módulos 3-4, see README.md "Caso de uso"):** a support/helpdesk agent.
It answers user questions from the Knowledge Base of FAQs built in módulo 4 (RAG); when that's not
enough, it falls back to the action-group Lambdas built in módulo 3 — `create_ticket` and
`get_ticket_status` — backed by DynamoDB. Keep new Lambdas/KB content aligned with this scenario
unless the user redirects it.

## Task tracking (`TASKS.md`)

[TASKS.md](TASKS.md) is the source of truth for implementation status at task granularity (finer
than the per-module table in `modules/README.md`). Check it before starting work to see exactly
what's outstanding in the current/next module, and update it (check off tasks, add the module's
`modules/NN-nombre.md` line) as work completes — don't let it drift like the summary above did.

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

State is remote (`backend "s3"`, `providers.tf`, set up in Módulo 2) — S3 bucket
`agentinfra-tfstate-<account_id>` with DynamoDB locking (`agentinfra-tfstate-lock-dev`). No local
`terraform.tfstate` is used day-to-day; it and `.terraform` stay gitignored regardless.

## Learning log (`/modules`)

`modules/` holds **learning notes, not Terraform modules** (this project has no submodules — see
Architecture notes below). One file per roadmap step (`01-fundamentos.md`, `02-backend-remoto.md`,
…, matching the numbering in README.md), covering what was built, new terminology, and key
concepts. When a roadmap module is completed, add its `modules/NN-nombre.md` file (see
`modules/01-fundamentos.md` for the expected shape) and update the status table in
`modules/README.md`. Conceptual notes not tied to one numbered module (e.g.
`modules/agent-harness.md`) go under the separate "Notas conceptuales" section of
`modules/README.md` instead of the numbered table.

## Architecture notes

- Root-module-only layout: `providers.tf` (Terraform/provider/backend config), `variables.tf`
  (`aws_region`, `project_name`, `environment`), `iam.tf` (Módulo 1 IAM resources), `backend.tf`
  (Módulo 2 S3+DynamoDB backend bootstrap), `action-groups.tf` (Módulo 3 action-group Lambdas +
  DynamoDB), `lambda/create_ticket/` and `lambda/get_ticket_status/` (Lambda source),
  `knowledge-base.tf` (Módulo 4 KB + S3 Vectors + FAQ bucket), `knowledge-base/faqs/` (FAQ
  content, uploaded via `aws_s3_object`), `outputs.tf`. No submodules yet — everything lives in
  the root module.
- AWS provider is pinned `~> 6.0` (bumped from `~> 5.0` in Módulo 4 — the `aws_s3vectors_*`
  resources need >= 6.24). Verify with `terraform plan` before any future provider bump that
  nothing already-deployed shows an unexpected diff, same as was done for this one.
- Resource naming convention: `${var.project_name}-<purpose>-${var.environment}` (see the IAM
  role names in `iam.tf`). Keep new resources consistent with this pattern.
- `default_tags` in `providers.tf` already stamps every resource with `Project`, `Environment`,
  `ManagedBy` — don't add those tags manually on individual resources.
- Bedrock is **not** free-tier (billed per token); IAM/Lambda/DynamoDB/S3 usage in this roadmap
  stays within AWS's always-free tier. When adding a resource that incurs cost, note it (the
  README calls this out per module in Spanish) so the pattern established there continues.
