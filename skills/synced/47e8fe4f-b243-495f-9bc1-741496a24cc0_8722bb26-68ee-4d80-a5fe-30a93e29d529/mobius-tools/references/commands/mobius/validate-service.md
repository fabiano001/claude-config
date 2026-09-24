---
name: validate-service
description: Validate service completeness (build, structure, and conventions)
argument-hint: <service-name> [--repo <repo>] [--pr <number-or-url>] [--branch <name>]
model: sonnet
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Validate Service

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or equivalent).
>
> This command performs deterministic structural checks — kustomize builds,
> YAML validation, file existence, and convention pattern matching. All
> checks have binary pass/fail outcomes with no generative output. Sonnet
> handles this reliably.

This command checks whether an EKS service is **complete** — not just
syntactically valid but also convention-compliant.

It catches:
- Build failures (`kustomize build` + `yq` rendered-manifest queries)
- Missing structural files (config.yaml, kustomization.yaml, values.yaml) and incomplete config.yaml fields
- ApplicationSet wiring issues: wrong source count, missing `goTemplate`, invalid `applicationsSync`, generator path mismatch
- Missing gateway/HTTPRoute, IRSA claims, anti-affinity, PDB, resource requests, security context
- Convention drift from platform standards across scheduling, security, networking, observability, secrets, and ArgoCD
- Live cluster validation via `--cluster-context`; Karpenter NodePool alignment; JSON output for CI/CD integration

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [Environment Model](../../docs/architecture/environment-model.md) — overlay structure, expected file layout
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — ApplicationSet discovery requirements
> - [Networking](../../docs/architecture/networking.md) — gateway/HTTPRoute conventions
> - [IRSA Integration](../../docs/architecture/irsa-integration.md) — when IRSA claims are expected
> - [Karpenter Autoscaling](../../docs/architecture/karpenter-autoscaling.md) — NodePool scheduling patterns, label conventions, taint coverage

---

## Two Operating Modes

### Mode A: Local validation (working directory)

Validate a service in a local repo checkout:

```
/mobius:validate-service cert-manager --service-repo ../iac-eks-addons
/mobius:validate-service api-node-payments --service-repo ../helm-charts
```

### Mode B: PR / branch validation (GitHub)

Validate changes from a PR or branch without requiring local checkout:

```
/mobius:validate-service api-node-payments --repo helm-charts
/mobius:validate-service api-node-payments --pr 185 --repo helm-charts
/mobius:validate-service api-node-payments --pr https://github.com/boatsgroup/helm-charts/pull/185
/mobius:validate-service api-node-payments --branch feat/add-payments --repo helm-charts
```

## CLI Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--service-repo PATH` | Path to service repo (required) | — |
| `--argocd-repo PATH` | Path to iac-eks-argocd repo | — |
| `--cluster-context CTX` | Validate against a live cluster (kubectl context name) | off |
| `--nodepool-repo PATH` | Path to repo with Karpenter NodePool definitions | auto-discovered |
| `--envs ENV1,ENV2` | Target environments | auto-discovered |
| `--chart-dir PATH` | Path to chart directory | auto-detected |
| `--strict` | Treat all warnings as failures | off |
| `--category CAT` | Run only checks in a category | all |
| `--output FORMAT` | Output format: `text` or `json` | text |
| `--skip-render` | Skip kustomize build rendering | off |
| `--enable-helm MODE` | Helm rendering: `auto`, `true`, `false` | auto |

### Categories

| Category | Check Prefixes | What It Covers |
|----------|---------------|----------------|
| `structure` | STRUCT-* | Directory layout, overlays, ApplicationSet, gateway, IRSA |
| `build` | BUILD-* | Kustomize build, Helm rendering |
| `scheduling` | SCHED-* | Anti-affinity, topology spread |
| `disruption` | PDB-* | PodDisruptionBudget |
| `hpa` | HPA-* | Autoscaling configuration |
| `resources` | RES-* | Resource requests/limits, CPU/memory ranges, ratios |
| `security` | SEC-* | Privileged mode, host namespaces, security context, capabilities, IRSA |
| `networking` | NET-* | Services, ports, probes, ingress/gateway |
| `observability` | OBS-* | ServiceMonitor, PrometheusRule, probe depth, metrics port |
| `labels` | NS-*, LAB-* | Namespace, label conventions |
| `deployment` | DEP-* | Deployment strategy, rollback safety |
| `argocd` | ARGO-* | ArgoCD config.yaml conventions, sync policy, git/helm settings |
| `secrets` | SECVAL-*, ESO-* | Hardcoded secrets, git secrets, ExternalSecret, env exposure |
| `daemonset` | DS-* | DaemonSet updateStrategy, tolerations, hostNetwork, priority |
| `cluster` | CLU-* | Live cluster validation: namespace, SA, PDB, HPA, deployment rollout, events |
| `karpenter` | KAR-* | Karpenter NodePool alignment: selector matching, taint coverage, architecture |

### JSON Output Contract

When `--output json` is used, the output is a JSON array:

```json
[
  {
    "id": "SCHED-AFF-001",
    "severity": "fail",
    "scope": "SCHED",
    "message": "replicaCount >= 2 but no podAntiAffinity configured",
    "workload": "my-deployment",
    "evidence": ""
  }
]
```

The `workload` field identifies which workload the check applies to in multi-workload services. Empty string for service-scoped checks.

Exit code is still 0 (pass) or 1 (fail) regardless of output format.

---

## Input Resolution

The LLM resolves inputs as follows:

| User provides | LLM action |
|---------------|------------|
| `--service-repo <path>` | Run `npx mobius-validate-service` directly on local path |
| `--repo <name>` only | Run `gh pr list --repo boatsgroup/<name> --state open`, present list, user picks |
| `--pr <number> --repo <name>` | Run `gh pr diff <number> --repo boatsgroup/<name>`, identify services touched |
| `--pr <full-url>` | Parse org/repo/number from URL, run `gh pr diff` |
| `--branch <name> --repo <name>` | Run `gh api repos/boatsgroup/<name>/compare/main...<branch>` to get diff |
| Nothing (just service name) | Ask: "Which repo is this service in?" |

For PR/branch mode, the LLM:
1. Fetches the diff to identify which services under `argocd/` are touched
2. Ensures those services are available locally (clone/checkout if needed)
3. Runs `npx mobius-validate-service` for each touched service
4. Reports results with actionable fix suggestions

---

## Execution Flow

### Step 0: Doc-First Gate

> **Module**: Read [`shared/doc-first-gate.md`](shared/doc-first-gate.md) and execute all steps.

**Target repo**: the service repo provided via `--service-repo` or resolved from `--repo`/`--pr`.

Reads docs to surface expected AWS dependencies. Findings inform Step 3 (convention analysis) — e.g., if docs mention AppConfig but no `appconfig` IAM action is in the XIRSARole, flag it. Offers the appropriate document command if docs are missing.

### Step 1: Resolve target

Determine the service repo, service name, and target environments from
user input. If PR/branch mode, fetch the diff first.

### Step 2: Run the deterministic validator

```bash
npx mobius-validate-service <service-name> \
  --service-repo <path> \
  --argocd-repo ../iac-eks-argocd \
  --chart-dir <path-to-chart>  # if chart is in the same repo
```

Arguments:
- `--service-repo`: Path to the repo containing `argocd/<service>/`
- `--argocd-repo`: Path to `iac-eks-argocd` for ApplicationSet checks (optional)
- `--chart-dir`: Path to the Helm chart directory for convention checks (optional; auto-detected)
- `--envs`: Comma-separated environments (optional; auto-discovered from overlays)

### Step 3: Interpret results

If the validator reports failures, the LLM provides:
- **What failed**: Exact check that failed
- **Why it matters**: What would break in production
- **How to fix**: Specific file edits or commands to resolve

### Step 4: Convention analysis (LLM-enriched)

Beyond what the shell script checks, the LLM also inspects:
- Whether overlay `values.yaml` gateway hostnames look correct
- Whether config.yaml `helm.repoURL` matches the ApplicationSet generator
- Whether the service follows patterns established by sibling services in the same repo
- Whether the PR is missing files that similar PRs included

This step uses the LLM's ability to compare against existing services —
something a shell script cannot do.

---

## Gateway Check (Primary Use Case)

The most common failure this command catches:

> A service's Helm chart has `templates/httproute.yaml` but the overlay
> `values.yaml` does not set `gateway.enabled: true`.

This happens when:
1. A service was migrated before gateway/route support was standardized
2. A PR was created from an older template that didn't include gateway config
3. Someone manually created the service files without the route section

The fix is always: add a `gateway:` block to the overlay `values.yaml`.

Use `envoy-public` for externally-reachable services, `envoy-internal` for cluster-internal mesh routing:

```yaml
# External traffic (public hostnames)
gateway:
  enabled: true
  hostnames:
    - "service.qa.svc.bgrp.io"
    - "www.qa.example.com"
  parentRefs:
    - name: envoy-public
      namespace: envoy-public
      sectionName: https
  pathPrefix: "/"

# Internal traffic only (service-to-service)
gateway:
  enabled: true
  hostnames:
    - "service.qa.svc.bgrp.io"
  parentRefs:
    - name: envoy-internal
      namespace: envoy-internal
      sectionName: https
  pathPrefix: "/"
```

For services with ALB listener rules, use the translation script:

```bash
bash ../mobius-tools/scripts/apply-listener-rule-translation.sh \
  --intake /tmp/<service>-intake.yaml \
  --overlay <service-repo>/argocd/<service>/overlays/<env>/values.yaml
```

### Production Readiness Checks

The validator runs modular best-practice checks organized by category. Each check has a stable ID for tracking and CI integration.

#### Scheduling & HA

| Check ID | Severity | Description |
|----------|----------|-------------|
| SCHED-AFF-001 | **FAIL** | Anti-affinity required when replicaCount >= 2 or HPA enabled |
| SCHED-AFF-002 | WARN | Anti-affinity should use soft preference (ecosystem convention) |
| SCHED-AFF-003 | WARN | Anti-affinity should use hostname topology key |
| SCHED-PDB-001 | WARN | PDB required for multi-replica workloads |
| SCHED-PDB-002 | WARN | PDB maxUnavailable should be sane |
| SCHED-PRI-001 | WARN | priorityClassName advisory for Deployment/StatefulSet workloads |

#### HPA / Autoscaling

| Check ID | Severity | Description |
|----------|----------|-------------|
| HPA-REQ-001 | **FAIL** | HPA requires resource requests for scaling metrics |
| HPA-REP-001 | WARN | HPA should not coexist with static replicaCount |
| HPA-MIN-001 | WARN | HPA minReplicas should be >= 2 for HA |
| HPA-MAX-001 | INFO | HPA maxReplicas informational |

#### Security

| Check ID | Severity | Description |
|----------|----------|-------------|
| SEC-PRIV-001 | **FAIL** | Containers must not run as privileged |
| SEC-HOST-001 | WARN | Containers should not use host namespaces |
| SEC-SA-001 | WARN | ServiceAccount should not use default |
| SEC-CTX-001 | WARN | Security context should be configured |
| SEC-NONROOT-001 | WARN | Containers should run as non-root |
| SEC-CAP-001 | WARN | Containers should drop ALL capabilities |
| SEC-IRSA-001 | WARN | IRSA-annotated ServiceAccount should be present for AWS-integrated workloads |

> In `--strict` mode, all WARN checks are elevated to FAIL.

#### Structure & Conventions

| Check ID | Severity | Description |
|----------|----------|-------------|
| STRUCT-DIR-001 | **FAIL** | Service directory must exist under argocd/ |
| STRUCT-BASE-001 | **FAIL** | base/kustomization.yaml must exist |
| STRUCT-OVL-001 | **FAIL** | overlays/ directory must exist |
| STRUCT-OVL-002 | **FAIL** | Each overlay must have config.yaml, kustomization.yaml, values.yaml |
| STRUCT-APPSET-001 | **FAIL** | ApplicationSet file must exist in iac-eks-argocd (checks both flat `applicationsets/<group>/<service>.yaml` and subdirectory `applicationsets/<group>/<service>/<service>.yaml` patterns) |
| STRUCT-HUB-001 | **FAIL** | Service must be wired into a hub kustomization — `hubs/.../applicationsets/kustomization.yaml` must reference the service's ApplicationSet |
| STRUCT-APPSET-002 | WARN | If ApplicationSet uses multi-source (`sources:`), verify 3-source pattern: Source 0 = Helm chart, Source 1 = `ref: values` service repo, Source 2 = Kustomize overlay |
| STRUCT-APPSET-003 | WARN | If ApplicationSet uses `goTemplate: true`, `goTemplateOptions: ["missingkey=error"]` must also be present |
| STRUCT-APPSET-004 | WARN | If ApplicationSet uses `templatePatch` for sync policy, inline `spec.syncPolicy.automated` must not also be present (double-definition) |
| STRUCT-APPSET-005 | **FAIL** | ApplicationSet `applicationsSync` — if present — must be a valid value: `create-only`, `create-update`, `create-delete`, or `sync` (`create-update-delete` is invalid and silently breaks the ApplicationSet) |
| STRUCT-APPSET-006 | **FAIL** | ApplicationSet generator glob pattern must match this service's config.yaml `git.overlayPath` — mismatch causes silent non-discovery regardless of pattern type |
| STRUCT-GW-001 | **FAIL** | Gateway must be enabled when chart has HTTPRoute template |
| STRUCT-IRSA-001 | WARN | IRSA claim should exist for api-node/webapp-node families |
| STRUCT-S3P-001 | WARN | s3-proxy should exist for portal-react family |

#### Resources

| Check ID | Severity | Description |
|----------|----------|-------------|
| RES-REQ-001 | WARN/FAIL | Resource requests must be configured for scheduling |
| RES-LIM-001 | WARN | Resource limits should be configured to prevent unbounded consumption |
| RES-REQ-CPU-001 | WARN | CPU requests should be within recommended range (10m-4000m) |
| RES-REQ-MEM-001 | WARN | Memory requests should be within recommended range (32Mi-8Gi) |
| RES-RATIO-001 | INFO | CPU limit-to-request ratio advisory |
| RES-SANE-001 | **FAIL** | Resource requests must not exceed limits |

#### Networking

| Check ID | Severity | Description |
|----------|----------|-------------|
| NET-SVC-001 | WARN | Deployment workloads should have a Service object |
| NET-PORT-001 | WARN | Service targetPort should match container port |
| NET-PROBE-001 | WARN/FAIL | Liveness and readiness probes should be configured |
| NET-PROBE-002 | INFO | startupProbe recommended for slow-starting applications |
| NET-ING-001 | WARN | Gateway/Ingress hostnames should be configured |

#### ArgoCD Conventions

| Check ID | Severity | Description |
|----------|----------|-------------|
| ARGO-CFG-001 | **FAIL** | config.yaml must exist in each overlay |
| ARGO-CFG-002 | **FAIL** | config.yaml addon must match directory name |
| ARGO-CFG-003 | **FAIL** | config.yaml environment must match overlay directory |
| ARGO-CFG-004 | **FAIL** | config.yaml must have `testBranch` field |
| ARGO-CFG-005 | **FAIL** | config.yaml `argocd.prune`, `argocd.selfHeal`, and `argocd.allowEmpty` must all be present |
| ARGO-CFG-006 | **FAIL** | config.yaml `git.overlayPath` must resolve to the actual overlay directory containing the config.yaml |
| ARGO-CFG-007 | WARN | config.yaml must have `labels.app.kubernetes.io/part-of` |
| ARGO-NS-001 | WARN/FAIL | Namespace should be configured (not default) |
| ARGO-SYNC-001 | WARN | ArgoCD sync policy should enable prune and selfHeal |
| ARGO-WAVE-001 | WARN | syncWave should be a quoted string |
| ARGO-GIT-001 | WARN | git.repoURL should reference boatsgroup org |
| ARGO-HELM-001 | WARN | helm.version should be pinned for reproducibility |
| ARGO-IGNORE-001 | WARN | HPA configured — ensure ignoreDifferences for /spec/replicas to prevent ArgoCD sync conflicts |

#### Observability

| Check ID | Severity | Description |
|----------|----------|-------------|
| OBS-SM-001 | WARN | ServiceMonitor should be configured for workloads with metrics |
| OBS-PR-001 | INFO | PrometheusRule advisory when ServiceMonitor exists but no alerting rules |
| OBS-LOG-001 | INFO | Logging configuration advisory (stdout/stderr best practice) |
| OBS-PROBE-DEPTH-001 | WARN | Liveness and readiness probes should have distinct paths |
| OBS-SCRAPE-001 | WARN | Metrics port should be defined when ServiceMonitor is enabled |
| OBS-XRAY-001 | **FAIL** | xray-daemon sidecar must not be present — EKS uses OTEL Collector + Tempo + Mimir + Loki, not xray |

#### Secrets & Credentials

| Check ID | Severity | Description |
|----------|----------|-------------|
| SECVAL-HARDCODED-001 | WARN | Hardcoded secrets detected in values.yaml |
| SECVAL-GITOPS-001 | **FAIL** | Raw Kubernetes Secret with data must not be committed to git |
| ESO-PRESENT-001 | INFO | ExternalSecret usage advisory for secret-referencing workloads |
| SECVAL-ENV-001 | WARN | Sensitive env var names should use valueFrom, not inline value |

#### DaemonSet

| Check ID | Severity | Description |
|----------|----------|-------------|
| DS-STRAT-001 | WARN | DaemonSet should define updateStrategy |
| DS-TOL-001 | WARN | DaemonSet should have tolerations for tainted nodes |
| DS-HOSTNET-001 | INFO | DaemonSet hostNetwork usage advisory |
| DS-PRIORITY-001 | WARN | DaemonSet should have priorityClassName set |
| DS-NOAFFINITY-001 | INFO | DaemonSet with podAntiAffinity is unusual |

#### Labels & Namespace

| Check ID | Severity | Description |
|----------|----------|-------------|
| NS-SET-001 | WARN/FAIL | Namespace must be explicitly set (not empty, not 'default') |
| LAB-STD-001 | WARN | Workloads should have app.kubernetes.io/name label |
| LAB-MATCH-001 | WARN | Deployment selector.matchLabels must align with pod template labels |
| LAB-POD-001 | WARN | Pod template should have app.kubernetes.io/name label |
| NS-MATCH-001 | INFO | Rendered namespace should match config.yaml helm.namespace |

#### Deployment Strategy

| Check ID | Severity | Description |
|----------|----------|-------------|
| DEP-STRAT-001 | INFO | Deployment strategy type advisory (RollingUpdate vs Recreate) |
| DEP-SURGE-001 | WARN/FAIL | RollingUpdate maxSurge + maxUnavailable deadlock detection |
| DEP-HISTORY-001 | WARN | revisionHistoryLimit 0 prevents rollback |
| DEP-PROGRESS-001 | WARN | progressDeadlineSeconds too low may cause false failures |
| DEP-MINREADY-001 | INFO | minReadySeconds advisory for readiness stabilization |
| DEP-GRACE-001 | INFO | terminationGracePeriodSeconds advisory for graceful shutdown |

#### Live Cluster Checks

| Check ID | Severity | Description |
|----------|----------|-------------|
| CLU-KUBE-001 | **FAIL** | kubectl must be available for cluster validation |
| CLU-CTX-001 | **FAIL** | Specified cluster context must exist in kubeconfig |
| CLU-CONN-001 | **FAIL** | Must be able to connect to the cluster |
| CLU-NS-001 | WARN | Namespace should exist on cluster |
| CLU-SA-001 | WARN | ServiceAccount should exist on cluster |
| CLU-PDB-001 | WARN | PDB should exist on cluster when file-based PDB check passes |
| CLU-HPA-001 | WARN | HPA should exist on cluster when file-based HPA check passes |
| CLU-DEPLOY-001 | WARN | Deployment rollout should be complete (no pending pods) |
| CLU-SYNC-001 | INFO | ArgoCD application sync status advisory |
| CLU-EVENTS-001 | WARN | Recent warning/error events in service namespace |
| CLU-ENV-001 | INFO | Environment consistency between config.yaml and cluster namespace |

#### Karpenter NodePool Alignment

| Check ID | Severity | Description |
|----------|----------|-------------|
| KAR-SRC-001 | SKIP/PASS | NodePool source discovery (file-based or --nodepool-repo) |
| KAR-SELECTOR-001 | **FAIL** | nodeSelector must match at least one known NodePool |
| KAR-TAINT-001 | WARN | Workload should have tolerations for target pool taints |
| KAR-TAINT-002 | WARN | Workload tolerates restricted taints (arc-runner, monitoring, bootstrap) |
| KAR-ARCH-001 | **FAIL** | Architecture constraint must be supported by at least one NodePool |
| KAR-BOOTSTRAP-001 | **FAIL** | Bootstrap pool targeting requires matching toleration |
| KAR-LIVE-001 | WARN | Karpenter CRDs should be installed on cluster (live mode) |
| KAR-LIVE-002 | WARN | File-based NodePool inventory should match cluster state (live mode) |
| KAR-LIVE-003 | WARN | NodePools should be in Ready state on cluster (live mode) |

The canonical anti-affinity pattern (from `external-dns/base/values.yaml`):

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: <addon-name>
          topologyKey: kubernetes.io/hostname
```
---

## Examples

### Validate a single service locally (helm-charts repo)

```
/mobius:validate-service api-node-payments \
  --service-repo ../helm-charts \
  --argocd-repo ../iac-eks-argocd
```

### Validate a service in an application repo (chart in app repo)

```
/mobius:validate-service webapp-nextjs-portal-platform \
  --service-repo ../portal-nextjs-platform \
  --argocd-repo ../iac-eks-argocd \
  --chart-dir ../portal-nextjs-platform/charts/webapp-nextjs-portal-platform
```

### Validate all services in a PR

```
/mobius:validate-service --pr 185 --repo helm-charts --argocd-repo ../iac-eks-argocd
```

The LLM identifies all services touched in PR #185 and validates each one.

### Validate a branch before opening a PR

```
/mobius:validate-service api-node-payments \
  --branch feat/add-payments \
  --repo helm-charts \
  --argocd-repo ../iac-eks-argocd
```

### Run only security checks

```
/mobius:validate-service cert-manager --service-repo ../iac-eks-addons --category security
```

### Strict mode (CI pipeline)

```
/mobius:validate-service api-node-payments \
  --service-repo ../helm-charts \
  --argocd-repo ../iac-eks-argocd \
  --strict --output json
```

### Skip rendering (fast mode)

```
/mobius:validate-service api-node-payments \
  --service-repo ../helm-charts \
  --argocd-repo ../iac-eks-argocd \
  --skip-render
```

### Validate with live cluster checks

```
/mobius:validate-service api-node-payments \
  --service-repo ../helm-charts \
  --argocd-repo ../iac-eks-argocd \
  --cluster-context bg-qa-eks
```

### Validate Karpenter NodePool alignment

```
/mobius:validate-service cert-manager --service-repo ../iac-eks-addons --category karpenter
```

### Validate with explicit NodePool repo
| `/mobius:debug-appset` | Diagnoses runtime ApplicationSet failures; validate-service catches them before merge |

---

## Why Summary

> **What it does:** Generates a plain-language "Why This Matters" summary at the end
> of command execution. Reads shared formatting rules and repo glossary from
> `shared/why-summary.md` and `shared/repo-roles.md`, then produces an output section
> that explains how many checks ran, what was audited, key findings, and what
> production problems the issues would cause if not fixed — written for engineers
> who may not know the platform internals.

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: validation

**Context hints**:
- "Impact opener" → state how many checks ran and how many issues found
- "What was accomplished" → describe what was audited and the key findings
- "Why it matters" → explain what production problems the issues would cause if not fixed
- "What happens next" → list fixes needed, re-validation command

**Repo breakdown guidance**:
- Service repo: explain what was checked in the service configuration
- iac-eks-argocd: if ApplicationSet checks were included, explain what was verified. Translate check IDs into plain language
