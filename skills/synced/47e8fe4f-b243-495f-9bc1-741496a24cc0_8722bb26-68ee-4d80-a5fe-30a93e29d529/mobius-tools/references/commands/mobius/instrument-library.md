---
name: instrument-library
description: Add OTEL API-only instrumentation to a Node.js library so consuming services get spans and metrics automatically
argument-hint: [library-repo-path]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Instrument a Node.js Library with OpenTelemetry API

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This command requires exported function criticality classification, deep codebase
> analysis via LSP and AST tooling, semantic convention enforcement, and API-only
> code generation (no SDK). Weaker models may add SDK packages to library deps
> (a hard error), generate incorrect tracer acquisition patterns, or produce metrics
> without cardinality-safe Views.

This command orchestrates the full `/mobius:instrument-library` flow in eight phases
(0–7). The engineer provides the library repo path, reviews the function instrumentation
plan, and the LLM handles analysis, code generation, test scaffolding, and docs
automatically.

## Architecture Context

> When you need platform reasoning beyond this spec:
> - [ADR-004: Standardized OTEL Instrumentation](../../docs/decisions/004-standardized-otel-instrumentation.md)
> - [RFC: Org-wide OpenTelemetry for Node.js Applications](https://boats-group.atlassian.net/wiki/spaces/DEV/pages/4804640770/RFC+Org+wide+OpenTelemetry+for+Node.js+Applications)

Key facts:
1. **API-only** — libraries use `@opentelemetry/api` ONLY. No SDK packages in production deps ever.
2. **No SDK init** — the consuming service initializes the OTEL SDK. The library never calls `NodeSDK.start()`.
3. **Zero-overhead no-op guarantee** — when no SDK is loaded, `@opentelemetry/api` is a pure no-op. Library overhead is zero.
4. **Consumer transparency** — library spans appear inside the consuming service's distributed trace automatically when the service has OTEL SDK running.
5. **Monorepo aware** — for multi-package repos, each package gets its own named tracer. Analysis and generation run per selected package.
6. **No smoke test phase** — libraries cannot run standalone. Signal validation uses in-memory SDK in unit tests instead.

---

## Canonical Rules

> **Reference**: Read [`instrument-library/canonical-rules.md`](instrument-library/canonical-rules.md) for all 30 constraints.

Key invariants:
1. No code generation before Phase 3 instrumentation plan is confirmed.
2. No completion claim before Phase 6 tests pass.
3. Feature branch MUST exist before Phase 6 (no generation on `main`).
4. Approved discovery plan (Phase 2.6) is the SINGLE SOURCE OF TRUTH for code, tests, and docs.
5. `@opentelemetry/api ^1.9.0` MUST be in `dependencies` (not `devDependencies`) — consumers need it transitively.
6. SDK packages (`sdk-node`, `sdk-trace-node`, exporters) MUST NEVER appear in library `dependencies` or `peerDependencies`.
7. Every generated metric MUST have a `View` with `attributeKeys` whitelist for cardinality control.
8. Every tracer MUST be acquired via `trace.getTracer(packageName, version)` — never construct SDK objects directly.

---

## Phase 0 — Git + Runtime + JIRA Preflight

> **Step 0a** (Git): Verify `gh auth status`, clean working tree (`git status --porcelain`), and current branch. If not on `main`, ask user to use current branch or start fresh from main. Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks.

> **Step 0b** (Runtime): Invoke `commands/mobius/shared/runtime-version-check.md` with **mandatory** enforcement. Auto-switch or auto-install Node.js via fnm/nvm/volta to match `.nvmrc`/`package.json engines.node`. Hard-stop if auto-install fails. Skip if no version spec found.

> **Step 0c** (JIRA): Prompt for JIRA ticket ID (strongly encouraged). Options: (1) enter ticket ID, (2) create one, (3) skip. Store as `jira_ticket_id` — flows into branch name, commit footer, and PR title.

---

## Phase 1 — Compatibility Check + OTEL API Info

Verify the target library can be instrumented before doing any analysis.

### Step 1.1: Locate Target Repository

Use provided path or CWD. Verify `package.json` exists. Extract `name`, `version`, `type`, `scripts`, `dependencies`, `devDependencies`, `peerDependencies`.

### Step 1.2: Runtime Checks

1. **Node.js version**: run `node --version`. Hard-stop if below 18.19.0.
2. **TypeScript version**: if TypeScript project, warn (not hard-stop) if below 5.0.4.
3. **Library classification**: verify target is a library (no server entrypoint, has exports, no HTTP listener). If service entrypoint detected, hard-stop and direct user to `/mobius:instrument-service`.

### Step 1.3: Monorepo Detection

Check for monorepo signals: `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`, `packages/` directory.

If monorepo detected:
- List all packages (most recently modified first, cap 20)
- If CLI argument targets a specific package, pre-select it
- If no argument, present full list and prompt user to select packages to instrument
- Record selected packages as `targets[]` with `{ package_path, package_name }`

If not monorepo: `targets = [{ package_path: repo_root, package_name: package.json name }]`

### Step 1.4: Existing OTEL Detection

Scan for `@opentelemetry/*` packages across all `targets[]`. If found:
- Prompt for merge strategy: `Merge` (default) / `Skip` / `Replace`
- Store as `otel_merge_strategy`
- If `sdk-node`, `sdk-trace-node`, or any exporter package found in `dependencies` → **WARN**: these must not be in library production deps. Offer to move to `devDependencies`.

### Step 1.5: Present OTEL API Package Info

Present the library-specific package selection:

```
OTEL Library Instrumentation Package Selection
═══════════════════════════════════════════════

Production dependencies (consumers get these transitively):
  @opentelemetry/api          ^1.9.0   ← ONLY SDK-agnostic package. NEVER 2.x.

Dev dependencies (test-only, never shipped):
  @opentelemetry/sdk-trace-base   ^2.5.1   ← In-memory SDK for tests
  @opentelemetry/sdk-metrics      ^2.5.1   ← Metrics SDK for tests (if metrics planned)

Optional: if library needs to define semantic conventions for its own spans:
  @opentelemetry/semantic-conventions  ^1.40.0  ← attribute name constants

DO NOT ADD:
  ✗  @opentelemetry/sdk-node         (service SDK — not for libraries)
  ✗  @opentelemetry/sdk-trace-node   (service SDK — not for libraries)
  ✗  @opentelemetry/exporter-*       (collector exporters — not for libraries)
  ✗  @opentelemetry/instrumentation-* (auto-instrumentation — not for libraries)
  ✗  @opentelemetry/sdk-node in peerDependencies (consumers choose their own SDK)
```

---

## Phase 2 — Discovery & Analysis

> **What it does:** For each package in `targets[]`, scans exported functions and methods,
> classifies each by operational criticality (🔴/🟡/🟢/⚪), identifies the operations
> most likely to fail or degrade in ways that affect consumers, plans span attributes,
> plans metrics (if applicable), and produces a structured instrumentation plan.

> **Module**: Read [instrument-library/discovery-analysis.md](instrument-library/discovery-analysis.md) and execute the full discovery workflow, including Steps 2.1 (package detection), 2.2 (exported function scan), 2.3 (criticality classification), 2.4 (attribute planning), 2.5 (metric planning), and 2.6 (confirm instrumentation plan).

---

## Phase 3 — Present Instrumentation Plan

Combine all analysis results into a single reviewable plan. Show one block per package in `targets[]`:

```
Instrumentation Plan: {library-name}
Mode: {single-package | monorepo — N packages selected}

--- Package: {package_name} ({package_path}) ---

Codebase Characteristics:
  Language:       TypeScript {version} / JavaScript
  Module system:  ESM / CJS
  Test framework: {vitest | jest | none}
  Package type:   {library}

Tracer:
  Name:    '{package_name}'
  Version: '{package_version}' (from package.json)

Function Instrumentation Tiers:
  🔴 CRITICAL — full span + error recording + attributes
    {function_name}: {rationale}
    ...
  🟡 STANDARD — span on entry/exit, error recording
    {function_name}: {rationale}
    ...
  🟢 MINIMAL — span only on error path
    {function_name}: {rationale}
    ...
  ⚪ SKIP — pure CPU/synchronous lookup, no I/O, no fallback risk
    {function_name}: {rationale}
    ...

Custom Metrics (if any):
  {metric_name}  {type}  {unit}  {description}
  ...

Span Attributes (library.* namespace):
  library.package       ← '{package_name}'
  library.operation     ← function name
  library.tenant        ← tenant id (if multi-tenant)
  {domain-specific attrs from discovery}

Proposed Files:
  {package_path}/src/telemetry/tracer.ts     — getTracer wrapper
  {package_path}/src/telemetry/spans.ts      — span wrapper utilities (if 🔴 fns exist)
  {package_path}/src/telemetry/metrics.ts    — meter + View definitions (if metrics planned)
  {package_path}/src/__tests__/telemetry.test.ts — in-memory SDK tests
  {package_path}/docs/observability.md       — consumer-facing signal reference

package.json changes:
  dependencies:    + @opentelemetry/api ^1.9.0
  devDependencies: + @opentelemetry/sdk-trace-base ^2.5.1
                   + @opentelemetry/sdk-metrics ^2.5.1 (if metrics planned)

--- [repeat per package] ---

Approve this plan? (yes / edit / start over)
```

User responds `yes` or field-level overrides. Once confirmed, APPROVED PLAN is locked — all downstream phases reference it.

---

## Phase 4 — Pre-Generation Validation Pass (HARD GATE)

After plan approval, run final validation:

| ID | Check | Requirement | Severity |
|---|---|---|---|
| `LIB-VAL-001` | `api_only` | No SDK packages (`sdk-node`, `sdk-trace-node`, exporters) in planned production deps | Error |
| `LIB-VAL-002` | `critical_coverage` | Every 🔴 CRITICAL function has span + error recording + attributes planned | Error |
| `LIB-VAL-003` | `tracer_acquisition` | All tracers use `trace.getTracer()` from `@opentelemetry/api` | Error |
| `LIB-VAL-004` | `naming_convention` | Metric names follow `{library}.{operation}.{signal}` pattern | Error |
| `LIB-VAL-005` | `cardinality_safety` | No high-cardinality attributes (user IDs, full URLs, arbitrary strings) in metric Views | Error |
| `LIB-VAL-006` | `noop_safety` | All span/metric calls wrapped so they are no-op when no SDK present | Error |
| `LIB-VAL-007` | `test_coverage` | In-memory SDK test planned for every 🔴 CRITICAL function | Error |
| `LIB-VAL-008` | `attribute_namespace` | Custom attributes use `library.*` or domain-specific namespace (no bare attribute names) | Warning |
| `LIB-VAL-009` | `version_in_tracer` | `trace.getTracer(name, version)` includes package version from `package.json` | Warning |
| `LIB-VAL-010` | `node_version` | Node.js version is `>= 18.19.0` | Error |
| `LIB-VAL-011` | `monorepo_tracer_isolation` | Each package in monorepo has its own named tracer | Error |
| `LIB-VAL-012` | `fallback_visibility` | If library has fallback/degradation paths (locale fallback, cache miss, default return), span attribute captures whether fallback fired | Error |

Fix all Error-severity failures before proceeding. Present validation report to user and require approval.

---

## Phase 5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` § Branch Creation Gate

If on `main`, create feature branch:
- With JIRA: `feat/<jira_ticket_id>-instrument-<library-name>`
- Without JIRA: `feat/instrument-<library-name>`

If user chose to keep existing branch in Phase 0, skip creation.

```
Branch Gate Status:
  ✅ {library-repo}   → feat/DEVOPS-1234-instrument-lib-node-localization

Proceeding to code generation.
```

---

## Phase 6 — Generate

> **Module**: Read [instrument-library/code-generation.md](instrument-library/code-generation.md) and execute all generation steps for each package in `targets[]`.

### Step 6.1: Tracer + Meter Files (per package)

Generate `src/telemetry/tracer.ts` for each package. Pattern:

```typescript
import { trace, type Tracer } from '@opentelemetry/api';
import { version } from '../../package.json';

let _tracer: Tracer | undefined;

export function getTracer(): Tracer {
  if (!_tracer) {
    _tracer = trace.getTracer('{package_name}', version);
  }
  return _tracer;
}
```

Generate `src/telemetry/metrics.ts` only when metrics are in the approved plan.

### Step 6.2: Span Wrappers (per package, 🔴 CRITICAL only)

Generate `src/telemetry/spans.ts` with wrapper utilities for 🔴 CRITICAL functions.

> **Module**: Read [instrument-library/code-generation.md](instrument-library/code-generation.md) § Span Wrapper Templates for the full wrapper pattern with error recording, attribute setting, and no-op safety.

### Step 6.3: Inject Wrappers Into Exported Functions

Apply AST-aware instrumentation calls into existing source files by tier:
- 🔴 CRITICAL: inject full span wrapper with attributes and error recording
- 🟡 STANDARD: inject span on entry/exit, error recording
- 🟢 MINIMAL: inject span only in catch/error paths
- ⚪ SKIP: no modification

Generate complete diff preview. Require user approval before Phase 6.4.

### Step 6.4: Package.json Update

Add to each targeted package's `package.json`:

```json
{
  "dependencies": {
    "@opentelemetry/api": "^1.9.0"
  },
  "devDependencies": {
    "@opentelemetry/sdk-trace-base": "^2.5.1",
    "@opentelemetry/sdk-metrics": "^2.5.1"
  }
}
```

Rules:
- Additive only — never remove existing dependencies
- `@opentelemetry/api` goes in `dependencies` (not `devDependencies`, not `peerDependencies`)
- SDK packages go in `devDependencies` only
- Run `npm install` / `pnpm install` after modifying package.json

### Step 6.5: Test Generation

> **Module**: Read [instrument-library/test-generation.md](instrument-library/test-generation.md) and generate telemetry emission tests for each package.

### Step 6.6: Observability Docs

> **Module**: Read [instrument-library/observability-docs-generation.md](instrument-library/observability-docs-generation.md) and generate `docs/observability.md` for each package.

---

## Phase 7 — Validate + Commit + Push + PR

### Step 7.1: Validation Gates

Run in order for each package in `targets[]`:

1. **Lint**: ESLint/Biome `--fix` on all generated and modified files
2. **TypeScript**: `tsc --noEmit` (or `nx run {package}:typecheck`)
3. **Tests**: run the generated telemetry tests + full existing test suite (`nx run {package}:test`)
4. **Package.json**: `JSON.parse` on modified package.json files
5. **Import resolution**: verify `@opentelemetry/api` imports resolve correctly
6. **No-op check**: verify tests include a case where no SDK is loaded and spans are no-ops

If any gate fails → fix before proceeding. Present Validation Summary.

### Step 7.2: Commit, Push, PR

> **Module**: Read [instrument-library/commit-push-pr.md](instrument-library/commit-push-pr.md) and execute all steps.

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md), then generate the Why Summary.

**Command type**: generative

**Context hints**:
- "Impact opener" → which library packages were instrumented and what operations now emit spans
- "What was accomplished" → OTEL API-only instrumentation, function criticality tiers, cardinality controls
- "Why it matters" → library spans appear inside consuming service traces automatically, fallback/degradation paths now visible without touching consumer code
- "What happens next" → 3 steps: consuming services need OTEL SDK running, verify spans appear in Grafana tempo, check fallback metrics
- "Zero cost" → no-op guarantee when consumer has no SDK loaded

**Repo breakdown guidance**:
- Library repo: all generated files — tracer/meter setup, span wrappers, tests, observability docs
- Consumer repos: no changes needed — SDK provides span context automatically
