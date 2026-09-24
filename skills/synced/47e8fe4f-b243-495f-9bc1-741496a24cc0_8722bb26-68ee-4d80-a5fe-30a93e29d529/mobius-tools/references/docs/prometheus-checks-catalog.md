# Prometheus Checks Catalog

This catalog registers all validator check IDs across the Mobius platform CLI tools.
It is the authoritative reference for:
- Check IDs, descriptions, and default severities
- False-positive controls (skip patterns, confidence thresholds, skip cascades)
- CI gating rules (which severities cause exit code 1)

Machine-readable output from every CLI validator uses these IDs in the `id` field.
Use `--output json` to get structured results consumable by CI pipelines or dashboards.

---

## Severity Legend

| Severity | Exit code | Description |
|----------|-----------|-------------|
| `fail` | 1 | Must fix before merge |
| `warn` | 0 (1 with `--strict`) | Should fix; blocks with `--strict` |
| `info` | 0 | Advisory only; never blocks |
| `pass` | 0 | Check ran and succeeded |
| `skip` | 0 | Check skipped due to cascade or missing data |

---

## SDOC-* — Service Docs Validator (`npx mobius-validate-service-docs`)

Checks produced by `validate-service-docs`. Compares generated service documentation
against actual source code for endpoints, config vars, dependencies, and staleness.

### Endpoints (SDOC-EP-*)

| Check ID | Default Severity | Description | False-Positive Controls |
|----------|-----------------|-------------|------------------------|
| SDOC-EP-001 | `fail` | Endpoint documented but not found in code (stale route) | Use `--skip-patterns` to exclude path prefixes (e.g. `/health`, `/metrics`) |
| SDOC-EP-002 | `fail` | Endpoint in code not documented | Use `--skip-patterns` to exclude path prefixes; raise `--confidence-threshold` to exclude low-confidence extractions |
| SDOC-EP-003 | `warn` | Endpoint count drift >10% between code and docs | Lower threshold in `policy.yaml` → `endpoint_count_drift_threshold`; use `--strict=false` to demote |
| SDOC-EP-004 | `warn` | HTTP method mismatch: path documented with different method than code | Verify code extraction confidence; use `--skip-patterns` to exclude ambiguous paths |
| SDOC-EP-005 | `info` | Low-confidence endpoints detected below `--confidence-threshold` | Raise `--confidence-threshold` to filter more aggressively; advisory only, never blocks |

**Skip cascade:** SDOC-EP-003, SDOC-EP-004, SDOC-EP-005 emit `skip` if SDOC-EP-001 or SDOC-EP-002 fire.

### Config (SDOC-CFG-*)

| Check ID | Default Severity | Description | False-Positive Controls |
|----------|-----------------|-------------|------------------------|
| SDOC-CFG-001 | `warn` | Config var documented but not found in code (stale variable) | Use `--skip-patterns` to exclude var name prefixes; CI/IRSA vars (`GITHUB_*`, `npm_*`, etc.) are always auto-excluded |
| SDOC-CFG-002 | `warn` | Config var in code not documented | Use `--skip-patterns` to exclude prefixes; CI-injected vars auto-excluded |
| SDOC-CFG-003 | `warn` | Sensitive variable not marked `sensitive: true` in docs | Use `--skip-patterns` with `varNamePatterns` regex to exclude known non-sensitive vars |
| SDOC-CFG-004 | `warn` | Required/optional mismatch between code and docs | Use `--skip-patterns` to exclude dynamic vars; verify Zod/Joi schema extraction |
| SDOC-CFG-005 | `info` | Config var count drift >20% (raw, pre-filter counts) | Advisory only; never blocks; reflects skip-pattern exclusions in raw total |

**Skip cascade:** SDOC-CFG-003, SDOC-CFG-004, SDOC-CFG-005 emit `skip` if SDOC-CFG-001 or SDOC-CFG-002 fire.

**Auto-excluded CI/IRSA vars** (never compared, never reported):
`CI`, `GITHUB_*`, `npm_*`, `NODE_ENV`, `AWS_REGION`, `AWS_DEFAULT_REGION`,
`AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_STS_REGIONAL_ENDPOINTS`

### Dependencies (SDOC-DEP-*)

| Check ID | Default Severity | Description | False-Positive Controls |
|----------|-----------------|-------------|------------------------|
| SDOC-DEP-001 | `fail` | Platform dep in `dependency-graph.yaml` not documented | Authoritative source is the graph YAML; update docs or remove from graph |
| SDOC-DEP-002 | `warn` | Runtime dep detected in code not in docs | Use `--skip-patterns` to exclude observability/infra deps (e.g. `prom-client`, `otel`) |
| SDOC-DEP-003 | `warn` | Dependency documented in docs not found in graph or code (stale) | Remove stale dep from docs, or add it to code/graph as appropriate |
| SDOC-DEP-004 | `info` | Internal service URL detected in code — verify it's in docs dependencies list | Advisory only; use `--skip-patterns` to suppress known cluster-internal URLs |

**Skip cascade:** SDOC-DEP-002, SDOC-DEP-003, SDOC-DEP-004 emit `skip` if SDOC-DEP-001 fires.

**Source rules** (must not be mixed):
- Platform deps → `ecosystem/dependency-graph.yaml` ONLY
- Runtime deps → code AST ONLY

**Default skip list** (auto-excluded from DEP-002):
`prom-client`, `pino`, `winston`, `dotenv`, `@opentelemetry/api`, `@opentelemetry/sdk-node`, `otel`

### Staleness (SDOC-STALE-*)

| Check ID | Default Severity | Description | False-Positive Controls |
|----------|-----------------|-------------|------------------------|
| SDOC-STALE-001 | `fail` | Docs directory does not exist — docs never generated | Run `/mobius:document-service` first |
| SDOC-STALE-002 | `fail` | Docs `generated_at` timestamp absent or unparseable | Re-run doc generation; check `docs/metadata.yaml` format |
| SDOC-STALE-003 | `warn` | Source files modified after `generated_at` (endpoint-bearing files) | Re-run doc generation; use `policy.yaml` → `staleness_warn_days` to tune |
| SDOC-STALE-004 | `warn` | Source files modified after `generated_at` (config-bearing files) | Re-run doc generation; same policy key |
| SDOC-STALE-005 | `warn` | `dependency-graph.yaml` updated after docs `generated_at` | Re-run doc generation after graph update |
| SDOC-STALE-006 | `info` | Docs older than 90 days regardless of source changes | Advisory only; tune threshold via `policy.yaml` → `staleness_info_days` (default 90) |

**Skip cascade:** SDOC-STALE-003, SDOC-STALE-004, SDOC-STALE-005, SDOC-STALE-006 emit `skip` if SDOC-STALE-001 or SDOC-STALE-002 fire.

---

## CI Gating Reference

```bash
# Standard — blocks on any `fail`
npx mobius-validate-service-docs <service> --service-repo <path>
echo "Exit: $?"   # 1 if any fail, 0 otherwise

# Strict — blocks on any `fail` OR `warn`
npx mobius-validate-service-docs <service> --service-repo <path> --strict
echo "Exit: $?"   # 1 if any fail or warn, 0 otherwise

# Category-scoped — only run staleness checks
npx mobius-validate-service-docs <service> --service-repo <path> --category staleness

# JSON output for dashboards / downstream processing
npx mobius-validate-service-docs <service> --service-repo <path> --output json
```

### Skip-Pattern File Format

```yaml
# .mobius/skip-patterns.yaml
endpoints:
  pathPrefixes:
    - /health
    - /healthz
    - /internal/
config:
  varNamePrefixes:
    - INTERNAL_
    - LEGACY_
  varNamePatterns:
    - "^TEST_.*"
deps:
  runtimeDepNames:
    - prom-client
    - otel
    - "org-shared/*"   # glob wildcard supported
```

---

## Related Validators

| CLI Command | Check ID Prefix | Catalog Section |
|-------------|-----------------|-----------------|
| `npx mobius-validate-service-docs` | `SDOC-*` | This document |
| `npx mobius-validate-service` | `SVC-*` | See `docs/command-reference.md` |
| `npx mobius-validate-graph` | `GRAPH-*` | See `docs/command-reference.md` |
| `npx mobius-validate-intake` | `INTAKE-*` | See `docs/command-reference.md` |
| `npx mobius-validate-wiring` | `WIRING-*` | See `docs/command-reference.md` |
