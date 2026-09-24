# Command Specs

These files are **AI agent instruction specs**, not user-facing documentation.

Each `.md` file defines the behavior of a `/mobius:*` slash command when run
inside Claude Code or OpenAI Codex. The AI agent reads the spec and executes
the workflow interactively with the engineer.

## How it works

```
Engineer runs:  /mobius:add-service my-api
                       │
                       ▼
Claude Code reads:  commands/mobius/add-service.md
                       │
                       ▼
Agent follows the spec: asks questions, generates files,
runs validators, creates branches and PRs
```

## For engineers

You don't need to read these files. Run `/mobius:help` to see available
commands, or read the [Engineer's Guide](../../docs/engineer-guide.md) for
a walkthrough of what each command does.

## For contributors

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for how to add or modify commands.

Each command spec has:
- **Frontmatter** — `name`, `description`, `argument-hint`, `model`
- **Canonical Rules** — hard constraints the agent must follow
- **Phased execution** — step-by-step flow the agent walks through

## Commands in this directory

| File | Command | Type |
|------|---------|------|
| `help.md` | `/mobius:help` | Navigation |
| `add-service.md` | `/mobius:add-service` | Generative |
| `update-service.md` | `/mobius:update-service` | Generative |
| `new-xrd.md` | `/mobius:new-xrd` | Generative |
| `new-hub.md` | `/mobius:new-hub` | Generative |
| `new-spoke.md` | `/mobius:new-spoke` | Generative |
| `new-project.md` | `/mobius:new-project` | Generative |
| `instrument-service.md` | `/mobius:instrument-service` | Generative |
| `migrate-ecs-service.md` | `/mobius:migrate-ecs-service` | Generative |
| `migrate-jenkins-to-gha.md` | `/mobius:migrate-jenkins-to-gha` | Generative |
| `debug-service.md` | `/mobius:debug-service` | Diagnostic |
| `debug-appset.md` | `/mobius:debug-appset` | Diagnostic |
| `validate-service.md` | `/mobius:validate-service` | Validation |
| `validate-intake.md` | `/mobius:validate-intake` | Validation |
| `validate-wiring.md` | `/mobius:validate-wiring` | Validation |
| `validate-graph.md` | `/mobius:validate-graph` | Validation |
| `validate-service-docs.md` | `/mobius:validate-service-docs` | Validation |
| `trace-impact.md` | `/mobius:trace-impact` | Analysis |
| `refresh-docs.md` | `/mobius:refresh-docs` | Maintenance |
| `document-repo.md` | `/mobius:document-repo` | Generative |
| `document-service.md` | `/mobius:document-service` | Generative |
| `document-iac.md` | `/mobius:document-iac` | Generative |

## Progressive spec loading

Large command specs are split into a core file and deep-dive modules.
The core file contains the command flow and routing instructions. Each
module contains detailed steps for a specific phase or concern.

```
add-service.md            ← core (phase flow + routing instructions)
add-service/
  helm-chart-resolution.md  ← loaded on demand by the agent
  research-phase.md
  commit-push-pr.md
```

The agent reads the core file first. When it reaches a routing instruction
like the one below, it loads the referenced module and executes those steps
before continuing:

```
> **Module**: Read [`add-service/helm-chart-resolution.md`](add-service/helm-chart-resolution.md)
>   and execute the discovery/validation flow before continuing to Phase 2.
```

This reduces upfront token consumption without changing the engineer's
experience — the same commands, same flow, same output.

| Command | Modules |
|---------|---------|
| `add-service` | `template-scaffold`, `dependency-intake`, `helm-chart-resolution`, `research-phase`, `operational-hardening`, `argocd-generation`, `terraform-generation`, `commit-push-pr` |
| `update-service` | `add-resource`, `bump-chart`, `add-environment` (reuses add-service generation submodules) |
| `debug-service` | `phase2-argocd`, `phase3-kubernetes`, `phase4-dependencies`, `phase4b-aws`, `reference-tables` |
| `instrument-service` | `discovery-analysis`, `otel-sdk-reference`, `semantic-conventions`, `code-generation/` (8 sub-modules), `test-generation`, `observability-docs-generation`, `smoke-test/` (5 sub-modules), `commit-push-pr` |
| `migrate-ecs-service` | `ai-propose-mode`, `deterministic-mapping-rules`, `commit-push-pr` |
| `migrate-jenkins-to-gha` | `repo-type-classifier`, `assessment-phase`, `config-generation`, `app-repo-generation`, `iam-role-generation`, `commit-push-pr`, `library-assessment`, `library-generation`, `library-commit-push-pr`, `lambda-assessment`, `lambda-generation`, `lambda-commit-push-pr` |
| `new-hub` | `ai-propose-mode`, `phase2-argocd-structure`, `phase3-crossplane`, `phase4-monitoring`, `phase5-bootstrap`, `commit-push-pr` |
| `new-spoke` | `ai-propose-mode`, `iam-trust-chain`, `phase2-argocd-registration`, `phase3-addon-overlays`, `phase4-crossplane`, `phase4b-observability`, `phase5-monitoring`, `commit-push-pr` |
| `new-xrd` | `commit-push-pr` |
| `document-repo` | `discovery-analysis`, `code-generation`, `commit-push-pr` |
| `document-service` | `deep-dive-analysis`, `content-generation`, `commit-push-pr` |
| `document-iac` | `document-iac/iac-analysis`, `document-iac/iac-generation`, `document-repo/code-generation`, `commit-push-pr` (base: `document-repo`) |

Commands without modules (`help`, `new-project`, `debug-appset`,
`validate-service`, `validate-intake`, `validate-wiring`, `validate-graph`,
`trace-impact`) are small enough to load in full.

## Shared modules

The `shared/` directory contains cross-cutting modules referenced by multiple commands:

| File | Purpose |
|------|---------|
| `shared/why-summary.md` | Format rules and examples for the "WHY THIS MATTERS" output section |
| `shared/repo-roles.md` | Plain-language glossary of all 20 platform repos (jargon-free) |
| `shared/change-safety-validation.md` | Universal pre-PR and post-PR safety gate (blockers, warnings, rollback, feedback scan) |
| `shared/session-directory.md` | Disk-backed session persistence protocol for long-running documentation commands |

Every command (except `help`) loads both shared modules at the end of execution
to generate a plain-language summary explaining what changed, why, and what each
repo's role is in the platform. This makes output understandable by developers
who may not have experience with Kubernetes, ArgoCD, or Crossplane.

Commands that create or modify files should also load
`shared/change-safety-validation.md` before completion to enforce universal
change-safety validation and post-PR feedback scanning.
