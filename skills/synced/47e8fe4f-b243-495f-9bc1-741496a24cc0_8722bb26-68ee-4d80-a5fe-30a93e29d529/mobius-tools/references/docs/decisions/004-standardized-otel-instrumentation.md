# ADR-004: Standardized OpenTelemetry Instrumentation for Node.js Services

**Status**: Proposed

**Date**: 2026-03-02

## Context

The Mobius platform runs a full observability stack — Prometheus, Grafana, Loki, and Tempo — with OTEL Collectors deployed as a DaemonSet on every EKS cluster. The infrastructure is ready. The problem is the application layer.

Individual Node.js services instrument themselves independently, producing:

- **Grafana index bloat** from non-standard or inconsistent resource attributes across services
- **Broken dashboards** caused by a mix of deprecated and current OTEL semantic conventions (e.g., `http.method` vs. `http.request.method`) appearing in the same Grafana instance
- **Runaway Prometheus storage** from unbounded cardinality — attributes like `url.full` and `user.id` slipping into metric dimensions
- **Incomplete observability** because most services emit traces only, with no structured logs and no application-level metrics
- **No regression safety** because telemetry emission is untested, so instrumentation breaks silently

All prior Mobius slash commands generate Kubernetes manifests. This ADR covers the first command that generates application-level code — `/mobius:instrument-service` — and the architectural decisions that govern how it works.

The full RFC is available at: https://boats-group.atlassian.net/wiki/spaces/DEV/pages/4804640770/RFC+Org+wide+OpenTelemetry+for+Node.js+Applications

## Decision

### 1. Standardized OTEL SDK initialization via `/mobius:instrument-service`

A new Mobius slash command generates all three OTEL signals — traces, metrics, and structured logs — for Node.js services. The command produces SDK initialization code, custom span wrappers, Metric Views, and test scaffolding alongside the application code. Engineers run the command once; the generated files integrate with the existing service without further scaffolding work.

### 2. Two discovery modes

**Mode A — Guided Questionnaire**: The command scans the codebase, builds an inventory of detected frameworks, routes, and dependencies, and presents the findings to the engineer. The engineer selects what to instrument. Output is deterministic given the same choices.

**Mode B — AI-Proposed SRE Mode**: The command performs deep analysis using LSP and AST tooling to classify every endpoint by criticality tier: 🔴 CRITICAL, 🟡 STANDARD, 🟢 MINIMAL, or ⚪ SKIP. It then proposes a tiered instrumentation plan with rationale. The engineer reviews and approves the plan, which is then committed to the repository as engineering documentation — a living record of what is instrumented and why.

### 3. Two-layer instrumentation architecture

**Layer 1 — Auto-instrumentation (approximately 80% of coverage)**: The command cherry-picks `@opentelemetry/instrumentation-*` packages based on detected dependencies. No manual code required. HTTP, database, message queue, and framework-level spans are captured automatically.

**Layer 2 — Auto-injected spans, metrics, and structured logging (approximately 20% of coverage)**: The command performs AST-aware transformations on existing route handlers and entry points to inject `tracer.startActiveSpan()` wrappers, metric recording calls, and structured logging at error points. Rollback safety is provided by git baseline capture and the runtime kill switch (`OTEL_SDK_DISABLED=true`) rather than local backup snapshots. The generated span wrapper functions still live in `src/telemetry/spans.{ts,js}`, but the command wires them into call sites automatically — engineers review the resulting diff in the PR rather than performing manual integration. Re-running the command on an already-instrumented service detects existing spans and offers MERGE, REPLACE, or SKIP per file.

### 4. Enforced semantic conventions

All generated code uses a shared schema for:

- **Required resource attributes**: `service.name`, `service.namespace`, `service.instance.id` — present on every span and metric from every service
- **Stable attribute names**: current OTEL conventions only (e.g., `http.request.method`, not the deprecated `http.method`)
- **Cardinality blocklist**: the following attributes are never used as metric dimensions — `url.full`, `url.path`, `url.query`, `user.id`, `db.query.text`
- **Standard metric names, units, and histogram buckets**: consistent across all services so Grafana dashboards work without per-service customization

### 5. SDK-level cardinality control via Metric Views

Generated initialization code includes `View` definitions with explicit `attributeKeys` whitelists for every metric. High-cardinality attributes are dropped at the SDK level, before export to the OTEL Collector. This is the primary defense against Grafana index bloat and unpredictable Prometheus storage growth — it operates regardless of what attributes an instrumentation library or third-party package happens to emit.

### 6. OTEL SDK 2.0 package baseline

All generated code targets a pinned SDK baseline:

- `@opentelemetry/sdk-trace-*` and `@opentelemetry/sdk-metrics`: stable 2.x series (`2.5.1`)
- `@opentelemetry/sdk-node` and exporters: experimental 0.2xx series (`0.212.0`)
- `@opentelemetry/api`: 1.x series (`1.9.0`) — independently versioned, stable ABI

`@opentelemetry/api` 1.x has a stable ABI contract. Instrumentation code written against it survives SDK upgrades without modification. Node.js >= 18.19.0 is required.

### 7. OTLP/HTTP transport

All three signals are exported via HTTP transport. The endpoint is read from the standard `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable, defaulting to `http://localhost:4318`. The OTEL Collector DaemonSet already running on every EKS cluster receives the data without additional configuration.

### 8. Custom metrics per critical endpoint

For each 🔴 CRITICAL endpoint identified in discovery, the command generates two metrics:

- `{service}.{operation}.duration` — Histogram, seconds
- `{service}.{operation}.count` — Counter, with a `success` / `failure` attribute

Each metric gets its own `View` with an `attributeKeys` whitelist. All metrics use `AggregationTemporality.DELTA` for compatibility with Grafana Mimir.

## Consequences

### Positive

- **Consistent resource attributes** across all services means Grafana indexes stay clean without per-service normalization rules.
- **SDK-level cardinality control** via Metric Views produces predictable Prometheus storage growth regardless of what third-party instrumentation emits.
- **All three signals from day one** — traces, metrics, and structured logs — closes the observability gap that traces-only services currently leave.
- **Automated tests verify telemetry emission**, so instrumentation regressions are caught in CI rather than discovered during an incident.
- **Engineering docs generated alongside code** — the approved discovery plan is committed to the repository, eliminating a separate documentation sprint.
- **Tiered approach focuses deep instrumentation on business-critical paths**, keeping generated code volume proportional to actual risk.
- **The discovery plan becomes living documentation**, reviewed and updated as the service evolves rather than written once and forgotten.
- **Zero manual integration required** — the command auto-injects instrumentation into existing handlers, so observability is fully functional after merging the PR. Engineers review the diff rather than performing per-call-site wiring.

### Negative

- **Generated code must be maintained by service teams.** The command produces a starting point, not a continuously managed output.
- **Pinned SDK versions require manual review on upgrade.** Staying on `2.5.1` / `0.212.0` means teams must consciously evaluate each new SDK release.
- **Node.js >= 18.19.0 may force runtime upgrades** on services still running older versions before they can adopt this instrumentation pattern.
- **Source file modifications require careful PR review** — AST-aware transformations handle standard handler patterns reliably, but complex or unconventional handler signatures may need manual adjustment after auto-injection.
- **AI-Proposed mode depends on LSP and AST tooling** to classify endpoints accurately. In repos where those signals are weak or unavailable, the proposed plan will be less precise.

### Neutral

- The command operates on a single repository. Monorepo support is deferred to a future iteration.
- Dockerfile and CI pipeline changes are documented as recommendations, not applied automatically.
- Auto-injection modifies source files in place with git-native rollback guidance and kill-switch support (`OTEL_SDK_DISABLED=true`). Re-runs are idempotent — existing instrumentation is detected and the engineer chooses MERGE, REPLACE, or SKIP per file.
- `@opentelemetry/api` 1.x stability means instrumentation code written today survives SDK 2.x upgrades without modification.
