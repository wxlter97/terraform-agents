# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`agent-infra-terraform`: a learning project building AWS infrastructure-as-code for AI agents
(AWS Bedrock Agents) with Terraform, staying inside the AWS free tier wherever possible.
Documentation and comments in this repo are written in Spanish — match that when editing
existing files.

This is currently **Módulo 6** of a planned multi-module roadmap (see README.md). Módulos 1-6 are
done and actually deployed (not just code-complete — verify against `terraform state list` /
`terraform plan`, not just by reading the `.tf` files, since earlier sessions assumed "code
exists" meant "applied" and that wasn't true for Módulo 3 until it was actually run):
- **Módulo 1 (IAM)** — `aws_iam_role.bedrock_agent_role` + `aws_iam_role.lambda_exec_role`.
  `bedrock_agent_role` is currently **unused** (see Módulo 5 note below) — kept, not deleted.
- **Módulo 2 (remote backend)** — `backend.tf` bootstraps an S3 bucket (versioned, encrypted,
  `prevent_destroy`) and a DynamoDB lock table; `providers.tf`'s `backend "s3"` block is now the
  active backend (migrated from local).
- **Módulo 3 (tool Lambdas)** — `action-groups.tf` + `lambda/create_ticket/`,
  `lambda/get_ticket_status/`: a `tickets` DynamoDB table and two Lambdas, using
  `lambda_exec_role` from Módulo 1. Their code was **rewritten in Módulo 5** for AgentCore
  Gateway's event/response contract (different from the original Bedrock Agents Classic shape).
- **Módulo 4 (Knowledge Base / RAG)** — `knowledge-base.tf`: FAQ content in S3 +
  `aws_bedrockagent_knowledge_base` backed by **S3 Vectors** (not Aurora/pgvector — that path is
  a confirmed dead end on this account, see below). Initial ingestion is pending an AWS
  account-verification gate, unrelated to the Terraform config — see
  [modules/04-knowledge-base.md](modules/04-knowledge-base.md).
- **Módulo 5 (the agent)** — `bedrock-agentcore.tf`: a `aws_bedrockagentcore_harness` (the agent),
  `aws_bedrockagentcore_gateway` + 3 `..._gateway_target` (Gateway wraps the Módulo 3 Lambdas and
  a new `query_faqs` Lambda — bridging to the Módulo 4 KB — as MCP tools). **Not** Bedrock Agents
  Classic (`aws_bedrockagent_agent`) — that's closed to this account, see below. See
  [modules/05-bedrock-agent.md](modules/05-bedrock-agent.md) for the full story.
- **Módulo 6 (API Gateway + proxy)** — `api-gateway.tf`: `aws_apigatewayv2_api` (HTTP API) +
  a `chat_proxy` Lambda that calls `InvokeHarness` and returns the reply. Deployed and
  live-tested — found and fixed a real missing IAM permission (AgentCore Memory, auto-provisioned
  by every harness even without an explicit `memory` block) along the way. See
  [modules/06-api-gateway.md](modules/06-api-gateway.md).

**Three account-level walls hit so far — check for these before assuming standard AWS behavior:**
1. **This AWS account is a "Free Plan" account type** (distinct from "free-tier eligible
   services") — it forces Aurora clusters into Express Configuration, which cannot attach a VPC
   or enable the RDS Data API that Bedrock's Aurora-as-KB integration requires. Confirmed by
   hands-on testing. Relevant if a future module reaches for RDS/Aurora.
2. **Bedrock Agents Classic (`aws_bedrockagent_agent*`) is closed to this account** — AWS put it
   in maintenance mode on 2026-07-30; accounts with no prior usage can't create new agents.
   Módulo 5 uses **Bedrock AgentCore** (`aws_bedrockagentcore_*`) instead — a different resource
   family with a different shape (Gateway + Gateway Target instead of action groups, Harness
   instead of Agent+Alias, no native Knowledge Base tool type). Don't reach for
   `aws_bedrockagent_agent*` resources in this project — they won't work on this account.
3. **This account hasn't submitted Anthropic's "model use case" form** — invoking any Anthropic
   model via Bedrock currently fails with `ResourceNotFoundException: Model use case details have
   not been submitted for this account`. Not fixable in Terraform/code — it's a business/compliance
   declaration only the account owner should submit (console: Bedrock → Model catalog → any
   Anthropic model → fill the form). `POST /chat` (Módulo 6) will 500 until this is done. Don't
   attempt to call `aws bedrock put-use-case-for-model-access` with invented form data.

Planned next modules (do not build ahead of the current module unless asked): CloudWatch
observability, and GitHub Actions CI/CD.

**Concrete use case (see README.md "Caso de uso"):** a support/helpdesk agent, fully wired
end-to-end as of Módulo 6 (blocked only by wall #3 above — infra-wise it's complete). It answers
user questions from the Knowledge Base of FAQs (Módulo 4, RAG, via the `query_faqs` tool); when
that's not enough, it falls back to `create_ticket` / `get_ticket_status` (Módulo 3) — backed by
DynamoDB — all reachable over the HTTP endpoint from Módulo 6. Keep new Lambdas/KB content aligned
with this scenario unless the user redirects it.

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
  (Módulo 2 S3+DynamoDB backend bootstrap), `action-groups.tf` (Módulo 3 tool Lambdas + DynamoDB),
  `lambda/create_ticket/`, `lambda/get_ticket_status/`, `lambda/query_faqs/` (Lambda source —
  `query_faqs` is Módulo 5, bridges the Gateway to the Módulo 4 KB), `lambda/chat_proxy/` (Módulo 6,
  calls `InvokeHarness`), `knowledge-base.tf` (Módulo 4 KB + S3 Vectors + FAQ bucket),
  `knowledge-base/faqs/` (FAQ content, uploaded via `aws_s3_object`), `bedrock-agentcore.tf`
  (Módulo 5: harness, gateway, gateway targets, their IAM roles), `api-gateway.tf` (Módulo 6: HTTP
  API + proxy Lambda), `outputs.tf`. No submodules yet — everything lives in the root module.
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
