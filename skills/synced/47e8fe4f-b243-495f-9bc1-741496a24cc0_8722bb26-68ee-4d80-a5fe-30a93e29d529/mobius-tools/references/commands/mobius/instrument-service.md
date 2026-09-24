---
name: instrument-service
description: Add standardized OTEL instrumentation to a Node.js service
argument-hint: [service-repo-path]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Instrument a Node.js Service with OpenTelemetry

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command requires endpoint criticality classification, deep codebase analysis
> via LSP and AST tooling, semantic convention enforcement against OTEL stable
> conventions, and three-signal code generation (traces, metrics, structured logs).
> Weaker models may misclassify criticality tiers, generate deprecated attribute names,
> or produce metrics without cardinality-safe Views. If using Codex CLI, prefer
> `codex exec --model o3`.

This command orchestrates the full `/mobius:instrument-service` flow end-to-end
in ten phases (0–9). The engineer provides the service repo path, selects a discovery
mode, reviews the instrumentation plan, and the LLM handles analysis, code generation,
test scaffolding, integration smoke testing, and validation automatically.

## Architecture Context

> When you need platform reasoning beyond this spec:
> - [ADR-004: Standardized OTEL Instrumentation](../../docs/decisions/004-standardized-otel-instrumentation.md)
> - [RFC: Org-wide OpenTelemetry for Node.js Applications](https://boats-group.atlassian.net/wiki/spaces/DEV/pages/4804640770/RFC+Org+wide+OpenTelemetry+for+Node.js+Applications)

Key facts: (1) First application-level command — generates TypeScript/JavaScript files that run at startup, not Kubernetes manifests. (2) OTEL Collector DaemonSet already deployed on every EKS cluster — application-side SDK sends signals to `http://monitoring-opentelemetry-collector.monitoring.svc.cluster.local:4318` (OTLP HTTP); this DNS name is identical on every cluster, so the same value is used in every overlay — no per-environment customization of the value is needed, but the env vars must still be set in each overlay's `values.yaml` (see Post-Merge Steps). See [SDK Endpoints](https://mobius.bgrp.io/observability/sdk-endpoints) for the full endpoint reference and Helm overlay pattern. (3) Single-repo scope — all generated files land in the service repo.

---

## Canonical Rules

> **Reference**: Read [`instrument-service/canonical-rules.md`](instrument-service/canonical-rules.md) for all 35 constraints.

Key invariants:
1. No code generation before Phase 3 instrumentation plan is confirmed.
2. No completion claim before Phase 7 validations pass.
3. Integration smoke test (Phase 8) is MANDATORY — no PR without passing smoke test.
4. Feature branch MUST exist before Phase 6 (no generation on `main`).
5. Approved discovery plan (Phase 2.8) is the SINGLE SOURCE OF TRUTH for code, tests, and docs.
6. Every generated metric MUST have a `View` with `attributeKeys` whitelist for cardinality control.
7. Dashboard "Why" descriptions MUST be derived from the approved plan — generic SRE boilerplate is a generation error.

---

## Phase 0 — Git + Runtime + JIRA Preflight

> **Step 0a** (Git): Verify `gh auth status`, clean working tree (`git status --porcelain`), and current branch. If not on `main`, ask user to use current branch or start fresh from main. Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks.

> **Step 0b** (Runtime): Invoke `commands/mobius/shared/runtime-version-check.md` with **mandatory** enforcement. Auto-switch or auto-install Node.js via fnm/nvm/volta to match `.nvmrc`/`package.json engines.node`. Hard-stop if auto-install fails. Skip if no version spec found.

> **Step 0c** (JIRA): Prompt for JIRA ticket ID (strongly encouraged). Options: (1) enter ticket ID, (2) create one, (3) skip. Store as `jira_ticket_id` — flows into branch name, commit footer, and PR title.

---

## Phase 1 — Compatibility Check + OTEL SDK Info

Verify the target service can be instrumented before doing any analysis.

1. **Locate repo**: use provided path or CWD. Verify `package.json` exists. Extract `name`, `version`, `type`, `scripts`, `dependencies`, `devDependencies`.
2. **Node.js version**: run `node --version`. Hard-stop if below 18.19.0 (OTEL SDK 2.0 minimum).
3. **TypeScript version**: if TypeScript project, warn (not hard-stop) if below 5.0.4.
4. **Existing OTEL detection**: scan for `@opentelemetry/*` packages and instrumentation files. If found, prompt for merge strategy: `Merge` (default) / `Skip` / `Replace`. Store as `otel_merge_strategy`.

### Step 1.5: Present OTEL SDK Package Info

> **What it does:** Loads the OTEL SDK package reference table and presents it to
> the user. Covers the three-tier versioning model (api 1.x, sdk 2.x, experimental 0.2xx),
> correct packages for traces/metrics/logs, and the auto-instrumentations wrapper.

> **Module**: Read [instrument-service/otel-sdk-reference.md](instrument-service/otel-sdk-reference.md) and present the SDK package table.

---

## Phase 2 — Discovery & Analysis

> **What it does:** Performs deep codebase analysis to produce the approved
> instrumentation plan. Detects framework, module system (ESM/CJS), TypeScript,
> test framework, and logger. Scans routes, dependencies, and external resource
> boundaries (8 categories). Classifies every boundary by risk tier. Resolves
> Grafana datasource roles from repository evidence. Produces a structured plan
> with endpoint tiers, failure modes, dependency SLI targets, startup boundaries,
> and Grafana datasource map — this plan governs all downstream generation.

> **Module**: Read [instrument-service/discovery-analysis.md](instrument-service/discovery-analysis.md) and execute the full discovery workflow, including Steps 2.4 (external resource boundary scan), 2.4b (Grafana datasource discovery), 2.6 (discovery mode choice), 2.7a/2.7b (guided questionnaire or AI-proposed SRE mode), and 2.8 (confirm instrumentation plan).

---

## Phase 3 — Present Instrumentation Plan

Combine all analysis results into a single, reviewable instrumentation plan.

| Section | Contents |
|---|---|
| Codebase Characteristics | Framework, module system, TypeScript, package manager, test framework, logger, Node.js version |
| Resource Attributes | `service.name`, `service.namespace`, `service.instance.id`, `service.version`, `deployment.environment.name` |
| Endpoint Instrumentation Tiers | All endpoints classified as 🔴 CRITICAL, 🟡 STANDARD, 🟢 MINIMAL, or ⚪ SKIP |
| Selected Auto-Instrumentations | Cherry-picked `@opentelemetry/instrumentation-*` packages based on detected deps |
| Custom Metrics Summary | Metric name, type, unit, target endpoint, cardinality-safe dimensions |
| Grafana Datasource Map | Datasource roles for metrics/logs/traces with evidence paths and fallback TODOs |
| Runtime Dependencies | Infrastructure containers, AWS/LocalStack services, internal API dependencies, ECS runtime config |

> **What it does:** Provides authoritative OTEL semantic convention rules for validating
> the proposed plan. Covers stable attribute names, metric naming pattern
> (`{service}.{operation}.{signal}`), cardinality rules, and log body field conventions.

> **Module**: Read [instrument-service/semantic-conventions.md](instrument-service/semantic-conventions.md) for attribute naming, cardinality rules, and metric conventions when validating the plan.

Present the plan in the format defined by the discovery-analysis module. User responds with `looks good` or field-level overrides. Once confirmed, the APPROVED PLAN is locked — all downstream phases reference it.

---

## Phase 4 — Pre-Generation Validation Pass (HARD GATE)

After the instrumentation plan is approved in Phase 3, run a final validation pass.

| ID | Check Name | Requirement | Severity |
|---|---|---|---|
| `VAL-001` | `route_coverage` | Every discovered route handler appears in the approved discovery plan | Error |
| `VAL-002` | `critical_metrics` | Every 🔴 CRITICAL endpoint has custom histogram + counter metrics | Error |
| `VAL-003` | `dependency_monitoring` | Endpoints with external dependencies include timeout monitoring | Warning |
| `VAL-004` | `logger_detection` | Logger library is detected and trace correlation is planned | Warning |
| `VAL-005` | `runtime_metrics` | `RuntimeNodeInstrumentation` is included in the plan | Error |
| `VAL-006` | `naming_convention` | Custom metric names follow `{service}.{operation}.{signal}` | Error |
| `VAL-007` | `cardinality_safety` | No blocklisted attributes are used in metric Views | Error |
| `VAL-008` | `signal_completeness` | Traces + metrics + logs are all present in the plan | Error |
| `VAL-009` | `hpa_recommendation` | Service type is classified and HPA metric recommendation exists | Warning |
| `VAL-010` | `node_version` | Node.js version is `>= 18.19.0` | Error |
| `VAL-011` | `framework_generation_coverage` | Every detected framework has explicit code-generation and injection templates selected in plan | Error |
| `VAL-012` | `async_propagation_coverage` | Detected queue/worker boundaries define propagation mode and required inject/extract test cases | Error |
| `VAL-013` | `dependency_identity_sli` | External dependency boundaries include identity attributes and per-dependency SLI rows in docs plan | Error |
| `VAL-014` | `startup_boundary_observability` | Startup-time external boundaries are listed with `startup.*` span coverage and failure monitoring notes | Error |
| `VAL-015` | `datasource_resolution` | Grafana datasource roles are resolved from repo files OR explicitly marked as TODO with search evidence | Warning |

Present validation report. Proceed to Phase 5 only after all Error-severity blockers are resolved and user approves.

---

## Phase 5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

**This phase MUST succeed before Phase 6 begins.**

If on `main`, create a feature branch:
- With JIRA: `feat/<jira_ticket_id>-instrument-<service-name>`
- Without JIRA: `feat/instrument-<service-name>`

If user chose to keep existing branch in Phase 0, skip creation.

```
Branch Gate Status:
  ✅ <service-repo>   → feat/PLAT-456-instrument-payments-api

Proceeding to code generation.
```

---

## Phase 6 — Generate

Two layers: Layer 1 (auto-instrumentation, ~80%) and Layer 2 (custom spans for 🔴 CRITICAL, ~20%).

> **Module**: Read [instrument-service/code-generation/doc-standards.md](instrument-service/code-generation/doc-standards.md) — apply JSDoc/TSDoc standards to all files in Steps 6.1–6.4.

### Step 6.1: SDK Init + Constants
> **Module**: [instrument-service/code-generation/layer1-sdk-init.md](instrument-service/code-generation/layer1-sdk-init.md) — apply ESM or CJS variant matching target repo's module system.

### Step 6.2: Custom Spans + Metrics
> **Module**: [instrument-service/code-generation/layer2-custom.md](instrument-service/code-generation/layer2-custom.md) — only when approved plan has 🔴 CRITICAL endpoints.

### Step 6.3: Framework + Logger
> **Module**: [instrument-service/code-generation/framework-selection.md](instrument-service/code-generation/framework-selection.md) — instrumentation selection matrix (frameworks, databases, HTTP clients, messaging) and code-style matching rules.

> **Module**: [instrument-service/code-generation/logger-setup.md](instrument-service/code-generation/logger-setup.md) — all 4 logger variant templates (pino, winston, no-logger console, EventEmitter experimental).

### Step 6.4: Inject, Wire, and Validate
> **Module**: [instrument-service/code-generation/injection-patterns.md](instrument-service/code-generation/injection-patterns.md) — injection patterns by framework and criticality tier.

> **Module**: [instrument-service/code-generation/async-and-boundaries.md](instrument-service/code-generation/async-and-boundaries.md) — queue/messaging propagation and external boundary instrumentation.

> **Module**: [instrument-service/code-generation/infra-rules.md](instrument-service/code-generation/infra-rules.md) — package.json merge rules, ESM/CJS detection, AST safety. Run Quick Enforcement Checklist before presenting generated code.

### Step 6.5: Observability Docs

> **What it does:** Generates `docs/observability.md` (signal inventory), `docs/dashboards.md` (dashboard map with service-specific "Why" descriptions from approved plan), and `docs/runbook.md` (alert playbooks + triage guide).

> **Module — Observability Docs (template part 1)**: Read [instrument-service/observability-docs/template-part1.md](instrument-service/observability-docs/template-part1.md) for context and the first half of the `docs/observability.md` template (Prerequisites → Startup Initialization Telemetry).
> **Module — Observability Docs (template part 2)**: Read [instrument-service/observability-docs/template-part2.md](instrument-service/observability-docs/template-part2.md) for the second half of the template (Structured Logs → Rollback Instructions).
> **Module — Observability Docs (rules)**: Read [instrument-service/observability-docs/rules.md](instrument-service/observability-docs/rules.md) for population rules, conditional section logic, completeness enforcement, and formatting rules before writing `docs/observability.md`.
> **Module**: Read [instrument-service/dashboard-docs-generation.md](instrument-service/dashboard-docs-generation.md) for `docs/dashboards.md` — "Why" derivation rules and quality gates.
> **Module**: Read [instrument-service/runbook-docs-generation.md](instrument-service/runbook-docs-generation.md) for `docs/runbook.md`.

### Step 6.6: Git Baseline + Inject + Wire + Diff Preview

Confirm clean working tree, record `otel_pre_instrumentation_sha`. Apply AST-aware injections by tier (🔴: full injection; 🟡: error logging only; 🟢/⚪: no modification). Add framework-native error handler. Wire entry point (`import './instrumentation'` as first import). Generate and present complete diff preview. Require user approval before Phase 7.

---

## Phase 7 — Validate + Test

> **What it does:** Generates telemetry emission tests by tier (auto-instrumentation, custom span, custom metric, structured log). Runs linter, TypeScript build, tests, package.json validation, import resolution, and pre-PR flaw scan. All gates must pass before Phase 8.

> **Module**: Read [instrument-service/test-generation.md](instrument-service/test-generation.md) — routing hub for test templates (core categories + verification categories).

> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md) and execute Phase A. Context: `risk_profile: application-code`, cardinality-safe metric views, idempotent injection, lifecycle safety.

Run in order: ESLint/Biome (`--fix`), `tsc --noEmit`, generated tests, `JSON.parse` on package.json, import resolution. Present Validation Summary before proceeding.

---

## Phase 8 — Integration Smoke Test (MANDATORY)

> **What it does:** Validates that the real service starts, serves HTTP, and emits all three telemetry signals to a real OTEL Collector. Generates `.observability/docker-compose.yaml`, `smoke-test-config.json`, and `scripts/otel-smoke-test.sh`. All generated files are committed so engineers can rerun the smoke test locally. **MANDATORY — Phase 9 must not proceed if this fails.**

> **Module (entry + prerequisites)**: Read [`instrument-service/smoke-test/setup.md`](instrument-service/smoke-test/setup.md) and execute §1–§2a: Phase 8 context, Docker/Compose checks, ECR authentication, dependent service resolution, and `smoke-test-config.json` generation.

> **Module (docker-compose stack)**: Read [`instrument-service/smoke-test/stack-generation.md`](instrument-service/smoke-test/stack-generation.md) and execute §3: generate `.observability/docker-compose.yaml`, `.gitignore`, LocalStack init script, and verify stack starts (Steps 8.3–8.5).

> **Module (service startup detection)**: Read [`instrument-service/smoke-test/execution-and-validation.md`](instrument-service/smoke-test/execution-and-validation.md) and execute §4: resolve start command, test config, health endpoint, and auth bypass strategy (Steps 8.6–8.8b).

> **Module (test script)**: Read [`instrument-service/smoke-test/test-script.md`](instrument-service/smoke-test/test-script.md) and execute §5: generate `scripts/otel-smoke-test.sh` with service-specific values baked in (Step 8.9).

> **Module (execute + validate)**: Return to [`instrument-service/smoke-test/execution-and-validation.md`](instrument-service/smoke-test/execution-and-validation.md) and execute §6–§8: run the script, handle results, three-signal validation rules, failure handling, and debug-until-pass policy (Steps 8.10–8.11).

> **Module (report + lifecycle)**: Read [`instrument-service/smoke-test/reporting-and-lifecycle.md`](instrument-service/smoke-test/reporting-and-lifecycle.md) and execute §9–§12: present the report, apply population and formatting rules.

**Gate**: All signals pass → Phase 9. Agent's code failures → agent debugs and fixes (no cap). Infrastructure issues → escalate to user. Docker unavailable → HARD STOP.

---

## Phase 9 — Commit, Push, and PR Creation

> **Prerequisite**: Phase 8 MUST have passed.

> **What it does:** Stages all generated and modified files, creates a conventional commit with JIRA reference, pushes the feature branch, and opens a PR with structured description including instrumentation plan summary, validation results, and dashboard/runbook guidance.

> **Module**: Read [instrument-service/commit-push-pr.md](instrument-service/commit-push-pr.md) and execute all steps.

---

## Why Summary

> **What it does:** Generates a plain-language "Why This Matters" summary explaining which service was instrumented, what signals are now emitted, the tiered instrumentation strategy, cardinality controls, smoke-test confidence, and three post-merge steps engineers must complete.

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md), then generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → which service was instrumented and what signals are now emitted
- "What was accomplished" → three OTEL signals, tiered instrumentation plan, cardinality controls
- "Why it matters" → standardized telemetry prevents Grafana index bloat and enables cross-service dashboards
- "What happens next" → 3 post-merge steps: wrap critical functions, add --import flag, verify tests
- "Integration confidence" → smoke test validated all 3 signals against a real OTEL Collector

**Repo breakdown guidance**:
- Service repo: all generated files — instrumentation code, tests, smoke test, observability stack, and docs
