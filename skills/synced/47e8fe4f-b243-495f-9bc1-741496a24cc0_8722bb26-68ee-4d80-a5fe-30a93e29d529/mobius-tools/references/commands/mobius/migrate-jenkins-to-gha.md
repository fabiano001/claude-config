---
name: migrate-jenkins-to-gha
description: Migrate a Jenkins api-node-* service, a Node.js library, or a Node.js Lambda from Jenkins to GitHub Actions using core-engineering-automation
argument-hint: <repo-name> [--include-modernization]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Migrate Jenkins to GitHub Actions

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command extracts configuration from multiple sources (existing repo config,
> ECS task definitions, Jenkinsfiles), generates files across multiple concerns
> (Docker, CI/CD workflows, Terraform IAM), and coordinates PRs across 1-2 repos.
> Weaker models may produce incorrect config extraction or malformed Terraform that
> fails silently.

This command migrates an existing Jenkins-based repo to GitHub Actions using the
`core-engineering-automation` reusable workflow library (`@v2`). It handles **three repo types**:
an `api-node-*` **service** (Docker + config + IAM + EKS deploy), a Node.js **library** (npm
package published to JFrog), or a Node.js **Lambda** (deployed via Jenkins `pipelineSAM()`,
moving to the `node-lambda-*` hub workflows). Step 1.0 classifies the repo and routes accordingly.
It processes **one repo at a time**.

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Core Engineering Automation README](https://github.com/boatsgroup/core-engineering-automation/blob/main/README.md) — reusable workflow library
> - [load-node-api-environment action](https://github.com/boatsgroup/core-engineering-automation/blob/main/.github/actions/ci/load-node-api-environment/action.yml) — how config/ files are consumed
> - [node-api-deploy-eks workflow](https://github.com/boatsgroup/core-engineering-automation/blob/main/.github/workflows/node-api-deploy-eks.yml) — EKS deployment flow

## Canonical Rules

- Process ONE repo at a time — never batch multiple repos in a single run.
- No file generation until the Assessment Phase reports PASS and the user confirms.
- Git preflight (`gh auth status`, clean working tree, branch check) must pass before assessment begins.
- Config generation extracts from existing sources only — never invent port numbers, hostnames, or PM2 settings.
- If config/ already exists in the repo, skip config generation entirely.
- If GHA workflows already exist and reference `core-engineering-automation@v2`, report "already migrated" and stop.
- IAM role Terraform must match the canonical `iam-role-github-oidc/aws` module pattern exactly.
- Work is not complete until PR(s) exist for every affected repo.
- JIRA ticket is prompted before work begins — encouraged but skippable.
- `--include-modernization` flag adds optional modernization (Cypress tests, API specs, monorepo client, test conversions) — recommended but not required for CI/CD migration.

---

## Git and JIRA Preflight (before assessment begins)

### Step 0a: Git Prerequisites

Verify for the CURRENT working directory:

1. `gh auth status` — GitHub CLI is authenticated. If not, hard-stop.
2. Working tree is clean: `git status --porcelain` returns empty. If dirty, hard-stop.
3. Check current branch:
   - If on `main`: pull latest (`git pull origin main`). Proceed normally.
   - **If NOT on `main`**: Ask the user:
     ```
     You're currently on branch `<current-branch>`.

     1. **Use this branch** — continue on the current branch
     2. **Switch to main and create new branch** — start fresh from main
     ```

### Step 0b: JIRA Ticket Prompt

```
Before we begin, is there a Jira ticket for this migration?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., DEVOPS-123)
2. **No ticket needed** → Skip JIRA (branch will use repo name only)
```

Store as `jira_ticket_id` (e.g., `DEVOPS-5523` or `null`).

---

## Step 1.0: Repo-Type Classification (MANDATORY — routes the whole command)

> **What it does:** Locates/clones the repo and classifies it as a deployable **service**
> (`api-node-*` EKS flow), a publishable **Node.js library** (npm package → JFrog), or a
> **Node.js Lambda** (deployed via Jenkins `pipelineSAM()`, moving to `core-engineering-automation`'s
> `node-lambda-*` hub workflows). All subsequent steps branch on `repo_type`.
> **Key behavior:** Classification uses `package.json` + filesystem signals, plus — lambda only —
> Jenkinsfile *content* (never the repo name; Jenkinsfile presence/absence alone is never a
> signal). The library and lambda branches are **always** confirmed with the user.
> **Module**: Read [`migrate-jenkins-to-gha/repo-type-classifier.md`](migrate-jenkins-to-gha/repo-type-classifier.md) and execute all steps before continuing.

**Routing:**
- `repo_type == service` → continue to **Step 1** (Assessment) and the service flow (Steps 2–6).
- `repo_type == library` → jump to **Step 1L** (Library Assessment) and the library flow; the
  service-only steps (2 Config, 3 App Repo Docker/ECS bits, 4 IAM Role, 6 Modernization) are
  **skipped**.
- `repo_type == lambda` → jump to **Step 1D** (Lambda Assessment) and the lambda flow; the
  service-only and library-only steps are **skipped**.
- `repo_type == none` → **stop**; the repo is either disqualified (container-image Lambda, real
  SAM/CFN stack, monorepo) or neither a service, a publishable library, nor an in-scope Lambda
  (e.g. private internal tooling), and has nothing to migrate.

---

## Step 1: Assessment Phase (MANDATORY — service branch)

> **What it does:** Looks up the repo in the migration readiness CSV, clones or
> locates the repo locally, detects existing GHA workflows, config directory,
> Dockerfile, and IAM OIDC role. Reports what needs to be created and asks for
> user confirmation before proceeding.
> **Key behavior:** STOPS for explicit user confirmation before any file generation.
> **Module**: Read [`migrate-jenkins-to-gha/assessment-phase.md`](migrate-jenkins-to-gha/assessment-phase.md) and execute all steps before continuing.

---

## Step 2: Config Generation (CONDITIONAL)

> **What it does:** If the repo does not have a `config/` directory, extracts
> configuration values from the repo's existing example config files and the ECS
> task definition, then generates `config/local.json`, `config/qa.json`, and
> `config/production.json`.
> **Key behavior:** Presents generated config files to the user for review before
> writing. Only generates if config/ is missing.
> **Module**: Read [`migrate-jenkins-to-gha/config-generation.md`](migrate-jenkins-to-gha/config-generation.md) and execute all steps. **Skip this step entirely if the assessment found config/ already exists.**

---

## Step 3: App Repo Generation

> **What it does:** Generates the Dockerfile, .dockerignore, .env.example,
> configureEnv.ts (if TypeScript), updates package.json, generates GHA workflow
> files (pr-ci-dispatch.yml + pr-command-dispatch.yml), and updates CODEOWNERS.
> **Key behavior:** Each generated file uses the standardized template from
> api-node-boats / api-node-template. Files that already exist are skipped.
> **Module**: Read [`migrate-jenkins-to-gha/app-repo-generation.md`](migrate-jenkins-to-gha/app-repo-generation.md) and execute all steps before continuing.

---

## Step 4: IAM Role Generation (CONDITIONAL)

> **What it does:** Checks if the `{app-name}-cicd-gha` IAM role exists in bg-qa.
> If missing, finds the correct Terraform repo (pattern A: app repo iac/, pattern B:
> terraform-stack-{name}, pattern C: terraform-stack-node10), and generates the
> OIDC IAM role using the canonical module.
> **Key behavior:** STOPS for user review of generated Terraform before writing.
> Only generates if the IAM role does not exist.
> **Module**: Read [`migrate-jenkins-to-gha/iam-role-generation.md`](migrate-jenkins-to-gha/iam-role-generation.md) and execute all steps. **Skip this step entirely if the assessment found the IAM role already exists.**

---

## Step 5: Commit, Push, and PR Creation

> **What it does:** Creates branches, commits changes, pushes to remote, and creates
> PRs for the app repo and optionally the Terraform repo. PRs cross-reference each
> other when both exist. Includes a completion report with PR URLs and next steps.
> **Key behavior:** Terraform PR should be merged first (IAM role must exist before
> GHA workflows can authenticate). Includes post-PR verification.
> **Module**: Read [`migrate-jenkins-to-gha/commit-push-pr.md`](migrate-jenkins-to-gha/commit-push-pr.md) and execute all steps before continuing.

---

## Step 6: Modernization (Optional - Only with --include-modernization flag)

> **What it does:** Brings the repo up to parity with api-node-template by adding Cypress
> E2E tests, modernizing API specs, setting up monorepo client generation, converting
> tests to TypeScript, and adding documentation (CHANGELOG.md, GLOSSARY.md).
> **Key behavior:** Only runs when user provides `--include-modernization` flag. These
> changes are recommended but NOT required for the CI/CD migration to work.
> **Module**: Read [`migrate-jenkins-to-gha/modernization.md`](migrate-jenkins-to-gha/modernization.md) and execute all steps.

**Gate: Skip if flag not provided** — If the user did not provide `--include-modernization`,
skip this step entirely and proceed to commit/push/PR.

---

## Library Flow (Step 1L onward — when `repo_type == library`)

When Step 1.0 classifies the repo as a **library**, the command follows the library branch
instead of Steps 1–6. A library migration produces **three** dispatcher workflows
(`pr-ci-dispatch.yml`, `pr-command-dispatch.yml`, and the library-only
`push-publication-dispatch.yml` that publishes to JFrog on push to `main`), minimal
`package.json` edits (remove Jenkins-era `preversion`/`postversion`), and a single-repo PR — no
Dockerfile, no `config/`, no IAM role, no Terraform.

> **Modules** (read and execute in order):
> 1. **Step 1L** — Library Assessment: [`migrate-jenkins-to-gha/library-assessment.md`](migrate-jenkins-to-gha/library-assessment.md)
> 2. **Step 2L** — Library Generation: [`migrate-jenkins-to-gha/library-generation.md`](migrate-jenkins-to-gha/library-generation.md)
> 3. **Step 3L** — Library Commit/Push/PR: [`migrate-jenkins-to-gha/library-commit-push-pr.md`](migrate-jenkins-to-gha/library-commit-push-pr.md)
>
> The library branch never falls through to the service steps (2–6); those generate service-only
> artifacts (Dockerfile, config/, IAM role) that a library must not have.

Library ground truth (dispatcher contents, reusable workflow names, JFrog registry, secrets) is
captured in [`reference-prs/README.md`](migrate-jenkins-to-gha/reference-prs/README.md) under
"Library migration — ground-truth findings", with verbatim diffs in
`reference-prs/lib-node-template-pr1.diff`, `lib-api-hapi-pr12.diff`, and `lib-node-geo-pr9.diff`.

---

## Lambda Flow (Step 1D onward — when `repo_type == lambda`)

When Step 1.0 classifies the repo as a **lambda**, the command follows the lambda branch instead
of Steps 1–6. A lambda migration produces up to **four** dispatcher workflows
(`pr-ci-dispatch.yml`, `pr-command-dispatch.yml`, `manual-deploy.yml`, and
`push-deploy-dispatch.yml`), a mandatory build-step fix when the repo has no `dist/`-producing
build script, and — unlike every other flow in this command — **two sequential PRs**, not one.

> **Modules** (read and execute in order):
> 1. **Step 1D** — Lambda Assessment: [`migrate-jenkins-to-gha/lambda-assessment.md`](migrate-jenkins-to-gha/lambda-assessment.md)
> 2. **Step 2D** — Lambda Generation: [`migrate-jenkins-to-gha/lambda-generation.md`](migrate-jenkins-to-gha/lambda-generation.md)
> 3. **Step 3D** — Lambda Commit/Push/PR: [`migrate-jenkins-to-gha/lambda-commit-push-pr.md`](migrate-jenkins-to-gha/lambda-commit-push-pr.md)
>
> The lambda branch never falls through to the service or library steps; those generate
> type-specific artifacts (Dockerfile/`config/`/IAM role; `push-publication-dispatch.yml`) a
> lambda must not have.

**Why two PRs, not one:** `push-deploy-dispatch.yml` triggers automatically on push to `main`.
Shipping it in the same PR as the Jenkinsfile removal risks Jenkins and the new GHA workflow both
deploying off the same merge. Phase 3a (CI + commands + Jenkinsfile removal) must merge first;
Phase 3b (adds `push-deploy-dispatch.yml` alone) is a separate PR from a fresh branch, opened only
after Phase 3a has merged. This is documented in full in `PLAN-BT-4104.md` (repo root) and the
Confluence source doc it was built from ("CORE-BLD-002: Node.js 20+ Lambda Migration").

**Ground truth this flow is verified against:** `lambda-node-template` (canonical workflow
bodies), `lambda-node-indexer-products` (a real repo running them), and the actual
`core-engineering-automation` reusables (`node-lambda-ci.yml`, `node-lambda-cd.yml`,
`node-lambda-deploy-production.yml`, `node-lambda-manual-deploy.yml`,
`node-lambda-command-processing.yml`, `load-node-lambda-environment/action.yml`) — read directly,
not assumed from the Confluence doc alone. `PLAN-BT-4104.md` §3 has the full writeup, including
two corrections that came from reading the reusables instead of guessing: `pipelineSAM()` is not
actually excluded by the doc's "SAM deployment model" language (it's packaging-only in this org),
and none of `publish`/`function_name`/`function_bucket`/`npm_ci_prod` have a workflow-input
equivalent to carry a value into.

Lambda ground truth (reusable workflow names, the `package.json.name`-is-the-deploy-target
dependency, and two real incidents from the first full execution — a build script that omitted
`node_modules` and broke production, and an `npm audit fix` resolved under the wrong local Node
version) is captured in
[`reference-prs/README.md`](migrate-jenkins-to-gha/reference-prs/README.md) under "Lambda
migration — ground-truth findings", with verbatim diffs in
`reference-prs/lambda-node-fetch-videos-pr{9,10,12}.diff`.

---

## Anti-Patterns

| Anti-Pattern | Why It Is Forbidden |
|--------------|---------------------|
| Inventing config values | Port numbers, PM2 settings must come from existing config or ECS. Wrong values cause silent deployment failures. |
| Modifying existing app logic | This is a CI/CD migration, not a refactor. Do not change server code, test files, or business logic. |
| Skipping user confirmation after assessment | Prevents generating files for the wrong repo or with incorrect assumptions. |
| Generating IAM role with wildcard policies | Security risk. Always use the standard 8-statement scoped policy. |
| Force-pushing | Overwrites others' work on the branch. |
| Processing multiple repos at once | Each repo has unique config, terraform location, and edge cases. Serial processing ensures correctness. |
| Adding ECS deployment config when config/ is missing and no ECS task def found | If ECS extraction fails, use defaults and flag for manual review — do not guess. |
| Classifying repo type by name (`lib-*`) or by presence/absence of a `Jenkinsfile` | Neither is dependable — libraries often lack the prefix and usually have no Jenkinsfile. Classify from `package.json` + filesystem signals only (Step 1.0). |
| Auto-routing to the library branch without user confirmation | The library flow generates different artifacts; a wrong guess is costly. Always confirm the library branch (Step 1.0.5), even at high confidence. |
| Generating a Dockerfile, `config/`, or IAM role for a library | Libraries are published to JFrog, not deployed. Those artifacts are service-only. |
| Dropping `push-publication-dispatch.yml` from a library migration | It is the library-only workflow that publishes the package to JFrog on push to `main`. Without it the library never publishes. |
| Treating a Jenkinsfile's `pipelineSAM()` call as disqualifying because the Confluence doc excludes "SAM deployment models" | In this org `pipelineSAM()` is packaging-only (`sam build` for native deps, then plain `update-function-code`) — verified against a real successful migration that used the identical bare call. The real disqualifier is a checked-in `template.yaml`/`samconfig.toml` (true SAM/CFN stack) or `pipelineLambdaImage()` (container-image deploy). |
| Shipping `push-deploy-dispatch.yml` in the same PR as `pr-ci-dispatch.yml`/`pr-command-dispatch.yml`/the Jenkinsfile removal | The two-phase protocol exists specifically to avoid Jenkins and the new GHA workflow both deploying off the same merge. Phase 3a and Phase 3b are separate PRs, sequenced by merge. |
| Inventing a `publish`, `function-name`, or `function-bucket` workflow input for a lambda migration | Confirmed by reading the `node-lambda-*` reusables directly — none of these exist. `function_name` mismatches are a blocking `package.json.name` fix; `publish`/`function_bucket`/`npm_ci_prod`/`on_*` Slack hooks are capability gaps to report, not values to translate into an input that doesn't exist. |
| Silently dropping a Jenkinsfile `on_success`/`on_failure`/`on_aborted` Slack hook, or a job-level `PUBLISH=true` | Both are real, observed patterns in this org's Lambda fleet. Report them as explicit behavior-change callouts requiring user sign-off — never drop them without saying so. |

---

## Reference Files

### Canonical Reference PRs (CONSULT FIRST)

Full diffs of two production-merged migrations are stored in `reference-prs/`. **When module docs and these diffs disagree, the diffs win** — they represent what actually shipped and passed CI/review.

| File | Source | Notes |
|---|---|---|
| `reference-prs/api-node-listing-monitor-pr8.diff` | [boatsgroup/api-node-listing-monitor#8](https://github.com/boatsgroup/api-node-listing-monitor/pull/8) (merged 2025-11-12) | Uses `specs/definitions/` layout |
| `reference-prs/api-node-search-pr15.diff` | [boatsgroup/api-node-search#15](https://github.com/boatsgroup/api-node-search/pull/15) (merged 2025-09-12) | Uses `specs/components/schemas/` layout; adds `/_status` uptime+timestamp; new `/_docs`; fuller Cypress specs |
| `reference-prs/README.md` | — | Cross-reference of where the two diffs diverge and which patterns to pick when |

### Legacy reference files

| File | Role |
|------|------|
| `api-node-boats/.github/workflows/pr-ci-dispatch.yml` | Golden reference for CI dispatch workflow |
| `api-node-boats/.github/workflows/pr-command-dispatch.yml` | Golden reference for command dispatch workflow |
| `api-node-boats` commit `064d5f55` | Older reference for full migration (config/, Dockerfile, etc.) |
| `terraform-stack-node10/shared/iam.tf` | Golden reference for IAM OIDC role pattern (multi-service stack) |
| `api-node-ai-provider/iac/github.tf` | Golden reference for IAM OIDC role pattern (app-repo) |
| `core-engineering-automation/.github/actions/ci/load-node-api-environment/action.yml` | How config/ files are consumed |
| `mobius-tools/data/api-node-eks-migration-readiness.csv` | Source of truth for repo eligibility |

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:migrate-ecs-ci-cd` | Adds EKS secrets to an already-migrated repo. This new command generates workflows WITH EKS secrets included, so `migrate-ecs-ci-cd` is not needed afterward. |
| `/mobius:migrate-ecs-service` | Migrates the ECS runtime to EKS (Helm charts, overlays, ArgoCD). Independent of this CI/CD pipeline migration. |
| `/mobius:validate-service` | Validates EKS service config. Run after `migrate-ecs-service`, not after this command. |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → state which service was migrated from Jenkins to GitHub Actions
- "What was accomplished" → describe the generated CI/CD pipeline, config, Dockerfile, and optionally IAM role
- "Why it matters" → the service now has standardized CI/CD with slash-command deployment (`/validate`, `/deploy`, `/deploy-eks`), replacing the legacy Jenkins pipeline
- "What happens next" → merge the PR(s), verify CI passes on a test PR, then the service is ready for GHA-based deployments

**Repo breakdown guidance**:
- App repo: generated CI/CD workflows, Docker configuration, and environment config
- Terraform repo (if applicable): IAM OIDC role enabling GitHub Actions to authenticate with AWS
