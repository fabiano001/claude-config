---
name: validate-service-docs
description: Validate generated service documentation against actual code (endpoints, config, dependencies, staleness)
argument-hint: <service-name> --service-repo <path> [--docs-dir <path>] [--strict] [--output json] [--category <cat>]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Validate Service Docs

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or equivalent).
>
> This command performs read-only reconciliation — extracting endpoints, config
> keys, and dependencies from source code and comparing against documentation.
> All checks are deterministic pattern-matching with no cross-repo generation.
> Sonnet handles the analysis reliably.

This command checks whether a service's generated documentation is **accurate**
— not just syntactically valid but also reconciled against what the code
actually does.

It catches:

- **Endpoint drift** — documented routes missing from code, or code routes not
  in docs
- **Config drift** — documented env vars missing from code, undocumented vars
  in use
- **Dependency drift** — platform deps mismatched against `dependency-graph.yaml`;
  runtime deps undocumented
- **Staleness** — docs generated before the last significant code change
- **[NEW]** Per-check IDs for machine-readable output (e.g., SDOC-EP-001)
- **[NEW]** JSON output mode for CI/CD integration
- **[NEW]** Category filtering to run only specific check groups
- **[NEW]** Strict mode that elevates all warnings to failures
- **[NEW]** Confidence thresholds and skip-pattern controls for false-positive management

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Agent Interop](../../docs/agent-interop.md) — Claude + Codex session bootstrap
> - [Ecosystem Map](../../ecosystem/master-map.md) — full platform topology
> - [Dependency Graph](../../ecosystem/dependency-graph.yaml) — authoritative cross-repo dep map
> - `commands/mobius/document-service.md` — what the docs generator produces
> - `commands/mobius/document-service/deep-dive-analysis.md` — Pass structure (endpoints, config, deps)

---

## CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--service-repo PATH` | Path to service source repo (required) | — |
| `--docs-dir PATH` | Path to generated docs directory | `<service-repo>/docs` |
| `--strict` | Treat all warnings as failures | off |
| `--category CAT` | Run only checks in a category | all |
| `--output FORMAT` | Output format: `text` or `json` | text |
| `--confidence FLOAT` | Minimum confidence threshold for endpoint/config extraction (0.0–1.0) | `0.7` |
| `--skip-patterns FILE` | Path to YAML file listing skip rules (path prefixes, env var name patterns, dep names) | — |

### Categories

| Category | Check Prefixes | What It Covers |
|----------|---------------|----------------|
| `endpoints` | SDOC-EP-* | Documented routes vs. code-extracted routes |
| `config` | SDOC-CFG-* | Documented env vars vs. code-extracted env vars |
| `deps` | SDOC-DEP-* | Platform deps vs. `dependency-graph.yaml`; runtime deps vs. code |
| `staleness` | SDOC-STALE-* | Last-generated timestamp vs. last significant code change |

### JSON Output Contract

When `--output json` is used, the output is a JSON object:

```json
{
  "results": [
    {
      "id": "SDOC-EP-001",
      "severity": "fail",
      "scope": "SDOC-EP",
      "message": "Endpoint GET /api/v1/payments documented but not found in code",
      "workload": "",
      "evidence": "docs/api-reference.md:47 vs src/routes/payments.ts"
    }
  ],
  "summary": {
    "total": 20,
    "pass": 16,
    "fail": 2,
    "warn": 1,
    "skip": 1,
    "info": 0
  }
}
```

The `workload` field is empty string for all service-docs checks (not workload-scoped).
The `evidence` field is mandatory on every result — file path and line number when available.

Exit code is `0` (pass or warn-only) or `1` (any fail, or any warn when `--strict`).

---

## Execution Flow

### Step 1: Locate docs and source

Resolve `--service-repo` and `--docs-dir`. Confirm:
- `<docs-dir>/` exists and contains at least one `.md` file
- `<service-repo>/` contains source code (look for `package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`)

If docs directory is absent, emit `SDOC-STALE-001` as `fail` and stop.

### Step 2: Extract from code (source of truth)

Run three parallel extraction passes:

**Pass A — Endpoint extraction**

Walk the source tree and extract route declarations using AST patterns:

| Framework | Pattern |
|-----------|---------|
| Express/Fastify/Hono | `app.<method>('path', ...)`, `router.<method>('path', ...)` |
| NestJS | `@Get()`, `@Post()`, `@Put()`, `@Patch()`, `@Delete()` decorators |
| Go (Gin/Echo/Fiber/Chi) | `r.GET()`, `e.GET()`, `app.Get()`, `r.Handle()` |
| Go `net/http` | `http.HandleFunc()`, `mux.HandleFunc()` |
| GraphQL | `type Query { ... }`, `type Mutation { ... }` resolver defs |
| gRPC | `.proto` `rpc` declarations |

De-duplicate by `method + path + handler`. Exclude:
- Files under `test/`, `tests/`, `__tests__/`, `spec/`, `*.test.*`, `*.spec.*`
- Files under `vendor/`, `node_modules/`, `dist/`, `build/`
- Auto-generated files (look for `// Code generated` or `# DO NOT EDIT` headers)

Per-endpoint output schema: `{ method, path, handler_file, handler_line, confidence }`

Assign `confidence`:
- `1.0` — string literal path with explicit method
- `0.8` — path from variable with traceable assignment
- `0.5` — path from config/env var (cannot resolve at analysis time)

Filter to `>= --confidence` threshold before comparison.

**Pass B — Config key extraction**

Scan sources in this priority order (higher = more reliable):

1. `.env.example`, `.env.template`, `.env.schema` — explicit declarations
2. `config/` directory YAML/JSON files — structured config
3. `process.env.VAR_NAME` / `os.Getenv("VAR_NAME")` — code references
4. Zod/Joi/Yup schema definitions — typed config
5. `env:` entries in `docker-compose.yml`, `.github/workflows/*.yml`

Per-variable output schema: `{ name, source_files, default, required, sensitive, evidence }`

Mark as `sensitive` if name contains: `SECRET`, `KEY`, `TOKEN`, `PASSWORD`, `CREDENTIAL`, `CERT`, `PRIVATE`.

Deduplicate: aliases (same var referenced from multiple files) collapse to one record.

**Pass C — Dependency extraction**

Two-level extraction — **never mix sources**:

| Level | Source |
|-------|--------|
| Platform deps | `ecosystem/dependency-graph.yaml` only — `dependencies:` key for this service |
| Runtime deps | Code AST only — import/require statements, client instantiations |

Runtime dep patterns to detect:

| Category | Code Patterns |
|----------|---------------|
| HTTP clients | `axios`, `fetch`, `got`, `http.NewRequest`, `net/http.Get` |
| Database | `pg`, `mysql`, `mongodb`, `prisma`, `gorm`, `sqlx`, `typeorm` |
| Redis | `redis`, `ioredis`, `go-redis` |
| AWS SQS/SNS/S3 | `@aws-sdk/client-sqs`, `aws.SQS`, `s3.GetObject` |
| Message queues | `amqplib`, `kafkajs`, `nats` |
| Internal services | `http://api-node-*`, `http://*.svc.cluster.local` |

### Step 3: Extract from docs (subject under test)

Parse the generated docs for declared:

**Endpoint inventory** — look in (in order):
1. `docs/api-reference.md` — primary API reference
2. `docs/README.md` — summary table
3. Any `docs/*.md` with `## Endpoints` or `## Routes` section

Extract `method + path` pairs from Markdown tables, code blocks, and route lists.

**Config inventory** — look in:
1. `docs/developer-guide.md` — environment variables section
2. `docs/README.md` — config summary
3. Any `docs/*.md` with `## Configuration` or `## Environment Variables` section

Extract variable name + description pairs from Markdown tables.

**Dependency inventory** — look in:
1. `docs/developer-guide.md` — dependencies section
2. `docs/README.md` — architecture/dependencies section
3. Any `docs/*.md` with `## Dependencies` or `## Integrations` section

Extract named services, databases, queues.

**Docs metadata** — read frontmatter or first heading for:
- `generated_at` / `last_updated` timestamp
- Generator version if present

### Step 4: Run checks

Run all checks (or filtered by `--category`). Apply skip patterns from
`--skip-patterns` before emitting any result. Use skip-cascade: if a parent
check fails, emit `skip` (not `fail`) for all dependent checks in that category.

See **Check Catalog** section for the full list.

### Step 5: Emit results

Text mode: print a human-readable summary grouped by category, with ✅/❌/⚠️/ℹ️/⊘ icons.

JSON mode: emit the JSON contract from above.

Print exit code hint at the end: `Passed` (exit 0) or `Failed` (exit 1).

---

## Check Catalog

### Severity legend

| Symbol | Severity | Exit code contribution |
|--------|----------|----------------------|
| ❌ | `fail` | Always contributes to exit 1 |
| ⚠️ | `warn` | Contributes to exit 1 only in `--strict` |
| ℹ️ | `info` | Never contributes to exit code |
| ⊘ | `skip` | Never contributes; emitted when parent check failed |

> In `--strict` mode, all `warn` checks are elevated to `fail`.

---

### Endpoints (SDOC-EP-*)

| Check ID | Severity | Description |
|----------|----------|-------------|
| SDOC-EP-001 | ❌ **FAIL** | Endpoint in docs not found in code (stale documented route) |
| SDOC-EP-002 | ❌ **FAIL** | Endpoint in code not found in docs (undocumented route) |
| SDOC-EP-003 | ⚠️ WARN | Endpoint count in docs differs from code by > 10% |
| SDOC-EP-004 | ⚠️ WARN | HTTP method mismatch: same path documented with different method than code |
| SDOC-EP-005 | ℹ️ INFO | Low-confidence endpoints detected (below threshold); manual review advised |

**Skip cascade:** SDOC-EP-003, SDOC-EP-004, SDOC-EP-005 skip if SDOC-EP-001 or SDOC-EP-002 fail
(endpoint inventory is already known-incomplete).

**False-positive controls:**

- Use `--confidence` to suppress low-confidence extractions (default 0.7)
- Use `--skip-patterns` to exclude specific path prefixes (e.g., `/internal/`, `/health`)
- Generated files (`// Code generated`) are excluded automatically

---

### Config (SDOC-CFG-*)

| Check ID | Severity | Description |
|----------|----------|-------------|
| SDOC-CFG-001 | ⚠️ WARN | Config var in docs not found in code (stale documented variable) |
| SDOC-CFG-002 | ⚠️ WARN | Config var in code not found in docs (undocumented variable) |
| SDOC-CFG-003 | ⚠️ WARN | Sensitive variable documented without `sensitive: true` flag or redaction note |
| SDOC-CFG-004 | ⚠️ WARN | Required variable documented as optional (or vice versa) |
| SDOC-CFG-005 | ℹ️ INFO | Config var count in docs differs from code by > 20% |

**Skip cascade:** SDOC-CFG-003, SDOC-CFG-004, SDOC-CFG-005 skip if SDOC-CFG-001 or SDOC-CFG-002 fail.

**False-positive controls:**

- Use `--skip-patterns` to exclude variable name prefixes (e.g., `NODE_`, `npm_`)
- CI-injected variables (`CI`, `GITHUB_*`, `AWS_*` from IRSA) are excluded by default
- Alias deduplication is applied before comparison

---

### Dependencies (SDOC-DEP-*)

| Check ID | Severity | Description |
|----------|----------|-------------|
| SDOC-DEP-001 | ❌ **FAIL** | Platform dependency in `dependency-graph.yaml` not documented in docs |
| SDOC-DEP-002 | ⚠️ WARN | Runtime dependency detected in code not documented in docs |
| SDOC-DEP-003 | ⚠️ WARN | Dependency documented in docs not found in `dependency-graph.yaml` or code |
| SDOC-DEP-004 | ℹ️ INFO | Internal service URL detected in code — verify it's in docs dependencies list |

**Skip cascade:** SDOC-DEP-002, SDOC-DEP-003, SDOC-DEP-004 skip if SDOC-DEP-001 fails.

**False-positive controls:**

- Platform deps are sourced from `dependency-graph.yaml` only — never from code
- Runtime deps are sourced from code only — never from the graph YAML
- Use `--skip-patterns` to exclude known infra-injected deps (e.g., `otel`, `prom-client`)

---

### Staleness (SDOC-STALE-*)

| Check ID | Severity | Description |
|----------|----------|-------------|
| SDOC-STALE-001 | ❌ **FAIL** | Docs directory does not exist — docs have never been generated |
| SDOC-STALE-002 | ❌ **FAIL** | Docs `generated_at` timestamp is absent or unparseable |
| SDOC-STALE-003 | ⚠️ WARN | Source files modified after `generated_at` (endpoint-bearing files) |
| SDOC-STALE-004 | ⚠️ WARN | Source files modified after `generated_at` (config-bearing files) |
| SDOC-STALE-005 | ⚠️ WARN | `dependency-graph.yaml` updated after docs `generated_at` |
| SDOC-STALE-006 | ℹ️ INFO | Docs are older than 90 days regardless of source changes |

**Skip cascade:** SDOC-STALE-003, SDOC-STALE-004, SDOC-STALE-005, SDOC-STALE-006 skip if
SDOC-STALE-001 or SDOC-STALE-002 fail (no valid timestamp to compare against).

**Staleness detection logic:**

```
1. Read docs generated_at timestamp T
2. Run: git log --since=T -- <source files> --oneline
3. Categorize changed files:
   - endpoint-bearing: routes/, controllers/, handlers/, *.router.*, *.proto
   - config-bearing: .env.example, config/, *.schema.ts
4. If any endpoint-bearing file changed → SDOC-STALE-003
5. If any config-bearing file changed → SDOC-STALE-004
6. Check git log --since=T -- ecosystem/dependency-graph.yaml → SDOC-STALE-005
```

---

## Skip Patterns File Format

The `--skip-patterns` flag accepts a YAML file:

```yaml
# skip-patterns.yaml
endpoints:
  path_prefixes:
    - /internal/
    - /health
    - /metrics
    - /readyz
  file_globs:
    - "src/internal/**"

config:
  var_name_prefixes:
    - NODE_
    - npm_
    - GITHUB_
    - CI
  var_name_patterns:
    - "^AWS_.*"  # IRSA-injected — not service-owned

deps:
  runtime_dep_names:
    - prom-client
    - "@opentelemetry/*"
    - otel
```

---

## Policy YAML (Per-Service Overrides)

Place a `validate-service-docs-policy.yaml` in the service repo root to
override default severities per category:

```yaml
# validate-service-docs-policy.yaml
# Zod schema mirrors scripts/validate-service/policy.yaml shape

endpoint_strict: false        # promote SDOC-EP warns to fail
config_strict: false          # promote SDOC-CFG warns to fail
deps_strict: true             # promote SDOC-DEP warns to fail
staleness_strict: false       # promote SDOC-STALE warns to fail

# Optional: override confidence threshold for this service
endpoint_confidence: 0.8

# Optional: inline skip patterns (same shape as --skip-patterns file)
skip:
  endpoints:
    path_prefixes:
      - /debug/
  config:
    var_name_prefixes:
      - LEGACY_
```

The `--strict` flag still overrides all policy settings (promotes everything).

---

## Examples

### Validate docs for a local service

```
/mobius:validate-service-docs api-node-payments --service-repo ../helm-charts
```

### Run only endpoint checks

```
/mobius:validate-service-docs api-node-payments --service-repo ../helm-charts --category endpoints
```

### CI strict mode with JSON output

```
/mobius:validate-service-docs api-node-payments --service-repo ../helm-charts --strict --output json
```

### With explicit skip patterns for internal routes

```
/mobius:validate-service-docs api-node-payments \
  --service-repo ../helm-charts \
  --skip-patterns ./skip-patterns.yaml
```

### With custom docs directory

```
/mobius:validate-service-docs api-node-payments \
  --service-repo ../helm-charts \
  --docs-dir ../helm-charts/services/api-node-payments/docs
```

### Validate only staleness (fast pre-commit check)

```
/mobius:validate-service-docs api-node-payments --service-repo ../helm-charts --category staleness
```

---

## GitHub Actions Integration

```yaml
- name: Validate service docs
  run: |
    npx mobius-validate-service-docs api-node-payments \
      --service-repo . \
      --strict \
      --output json \
      > validation-report.json
  continue-on-error: false

- name: Upload validation report
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: service-docs-validation
    path: validation-report.json
```

Exit code `1` will fail the workflow automatically when `--strict` is set.

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:document-service` | Generates the docs that validate-service-docs audits |
| `/mobius:validate-service` | Validates Kubernetes/Helm/ArgoCD service wiring (orthogonal) |
| `/mobius:refresh-docs` | Scans all repos for stale docs; validate-service-docs checks one service in depth |
| `/mobius:trace-impact` | Blast radius analysis; validate-service-docs checks whether impacted docs are current |

---

## Why Summary

> **What it does:** Generates a plain-language "Why This Matters" summary at the end
> of command execution. Reads shared formatting rules and repo glossary from
> `shared/why-summary.md` and `shared/repo-roles.md`, then produces an output section
> that describes what was extracted from code vs. declared in docs, the key
> discrepancies found, and what would mislead engineers or LLM agents if stale
> docs are used for platform decisions.

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: validation

**Context hints**:
- "Impact opener" → state how many checks ran, how many categories, and how many issues found
- "What was accomplished" → describe what was extracted from code vs. what was declared in docs, and the key discrepancies
- "Why it matters" → explain what would mislead engineers or LLM agents if stale docs are used for decisions
- "What happens next" → list whether to fix docs or re-run `/mobius:document-service`, then re-validate

**Repos checked guidance**:
- Service repo: explain what was scanned (routes, config, imports) and what the docs gap means for day-to-day development
