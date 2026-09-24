# Workflow: Adding a New EKS Addon

> **Terminology note**: In this workflow, `addon` is the deployment unit name used
> in file paths and legacy naming. For most engineers, this is equivalent to
> creating/deploying a new service on EKS.

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order; each step has a verification
> command so you can confirm success before proceeding.

---

## Purpose

Creates a new self-service service deployment ("addon" in repo naming) in a
**service repo** and wires up the
corresponding ArgoCD project permissions in `iac-eks-argocd`. Use this when
a new platform service needs to be deployed to EKS clusters via GitOps.

Default to an engineer-owned self-service repository for addon configs. Use
`iac-eks-addons` or `iac-eks-observability` only for platform-managed DevOps
workloads. In all cases, the addon's ApplicationSet generator must scan the
same service repo that contains `argocd/<addon>/overlays/<env>/config.yaml`.

**When to use this workflow**:
- Adding a Helm-chart-based platform service to one or more clusters
- Adding a service that needs an AWS IAM role (IRSA)
- Adding a service to a new environment overlay

---

## Preflight Gate (MANDATORY)

> **STOP — Before generating any files, answer Q0, select intake mode, and complete all checklists.**

### Q0: Which service repo hosts this addon's config.yaml?

**This question MUST be answered FIRST.** Do not proceed until you have a definitive answer.

```
Q0: Which repository will contain argocd/<addon>/overlays/<env>/config.yaml?
```

Rules:
- **If an ApplicationSet already exists for this addon**: The service repo MUST
  match the `generators[].git.repoURL` in that ApplicationSet. Check with:
  ```bash
  kubectl get applicationset -n argocd <addon> -o yaml | grep -A4 "git:" | grep repoURL
  ```
- **If creating a new ApplicationSet**: Choose the service repo FIRST, then set
  the ApplicationSet's `generators[].git.repoURL` to match.
- **DO NOT generate files until Q0 is answered.**

### Q1: Intake Mode Selection

After Q0, select the intake mode:

```
Q1: Which intake mode?
    a) deterministic - You provide all values directly
    b) ai-propose    - AI researches and proposes values for your approval
```

- **deterministic**: User fills all intake fields manually
- **ai-propose**: LLM researches, proposes values with evidence, waits for approval

If `ai-propose`, see `commands/mobius/add-service.md` for the proposal workflow.
Set `proposal_accepted: true` only after user explicitly accepts.

### Preflight Checklist

Before proceeding to Step 1, verify ALL of the following are captured:

| # | Item | Value | Status |
|---|------|-------|--------|
| 1 | Intake mode selected | `deterministic` / `ai-propose` | [ ] |
| 2 | Service repo URL captured | `https://github.com/boatsgroup/<repo>` | [ ] |
| 3 | Addon name captured (kebab-case) | `<addon>` | [ ] |
| 4 | Target environments captured | `bg-qa`, `bg-prod`, etc. | [ ] |
| 5 | Namespace strategy confirmed | `dedicated` / `shared` / `bootstrap` | [ ] |
| 6 | ApplicationSet existence confirmed | Yes / No | [ ] |
| 7 | Generator scope validated (if appset exists) | repoURL + path match | [ ] |
| 8 | If ai-propose: proposal accepted | `true` / N/A | [ ] |
| 9 | Helm version verified (V1) | `helm show chart` passed | [ ] |
| 10 | Values schema verified (V2) | `helm show values` reviewed | [ ] |
| 11 | Image config verified (V3) | default or override confirmed | [ ] |
| 12 | Kustomize API verified (V4) | `kustomize build` passed | [ ] |
| 13 | Chart characteristics inspected | CRDs, hooks, probes, SA | [ ] |
| 14 | AWS resources determined | `none` / `irsa-only` / `irsa-and-xrd` / `xrd-only` | [ ] |
| 15 | Probes health verified (V5) | Probes exist and match config | [ ] |
| 16 | SA name match verified (V6, if IRSA) | Chart SA = XIRSARole SA | [ ] |
| 17 | CRDs impact verified (V7, if CRDs) | SSA + preserveResources confirmed | [ ] |
| 18 | XRD exists verified (V8, if XRD claims) | All XRDs registered | [ ] |
| 19 | Addon classified | `critical-infrastructure` / `workload-supporting` / `daemonset` | [ ] |
| 20 | Hardening profile confirmed | Scheduling + HA + resources | [ ] |
| 21 | Git prerequisites verified | `gh auth status` + clean working tree | [ ] |
| 22 | JIRA ticket captured (if applicable) | Ticket ID or skip confirmed | [ ] |

### Using the Intake Template (Recommended)

For deterministic validation, fill out the intake template and run the validator:

```bash
# 1. Copy the intake template
cp docs/workflows/services/add-service-intake.yaml /tmp/my-service-intake.yaml

# 2. Fill in all required fields (especially service_repo_url)

# 3. Complete the Version-Lock Verification Gate (see below)

# 4. Validate before proceeding
npx mobius-validate-intake add-service /tmp/my-service-intake.yaml

# 5. If an ApplicationSet already exists, validate against it
npx mobius-validate-intake add-service /tmp/my-service-intake.yaml \
  ../iac-eks-argocd/applicationsets/core-infrastructure/<addon>.yaml
```

The validator ensures:
- All required fields are non-empty
- `service_repo_url` matches the ApplicationSet generator (if provided)
- `expected_generator_path` matches the ApplicationSet file path
- All verification booleans are `true`
- Version pinning rules (no `latest` for helm or image)
- Image override fields complete when `image_strategy: override`

### Operational Hardening (ai-propose mode)

When using `ai-propose` intake mode, the LLM must research and propose an
operational hardening profile covering scheduling, HA, resources, and monitoring.

#### Classification

| Category | Criteria | Scheduling | HA | Enforced |
|----------|----------|-----------|-----|----------|
| `critical-infrastructure` | Manages nodes, networking, DNS, secrets, LB, certs | Bootstrap node + control tolerations | replicas ≥2, PDB, anti-affinity | Anti-affinity + PDB **REQUIRED** when replicas ≥2 |
| `workload-supporting` | General platform service | General nodes (no nodeSelector) | replicas ≥2 recommended | Anti-affinity + PDB **REQUIRED** when replicas ≥2 |
| `daemonset` | Chart deploys DaemonSet(s) | Runs everywhere | N/A | Anti-affinity/PDB **SKIPPED** |

#### Enforcement Rules

The intake validator ENFORCES these rules (FAIL, not warn):

| Condition | Required Fields | Reason |
|-----------|----------------|--------|
| `replicas >= 2` | `anti_affinity`, `pdb_max_unavailable` | HA pods must spread; PDB prevents total eviction |
| `uses_hpa: true` | `anti_affinity`, `resources_requests_cpu` or `resources_requests_memory` | HPA-scaled pods must spread; HPA needs metrics |
| `uses_hpa: true` + `replicas` set | FAIL | HPA owns replica count — static replicas conflict |
| `addon_class: daemonset` | Skip affinity/PDB | DaemonSets run on every node by definition |

**Canonical anti-affinity pattern** (95% of ecosystem uses this exact pattern):

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

**Key conventions:**
- Always **soft** (preferred) anti-affinity — hard affinity deadlocks rolling updates on bootstrap nodes
- Weight always **100**
- Topology key always `kubernetes.io/hostname`
- Multi-component charts add `app.kubernetes.io/component: <component>` to matchLabels
#### Research Steps

1. Read codebase conventions:
   ```bash
   cat ../iac-eks-addons/argocd/karpenter/base/values.yaml
   cat ../iac-eks-addons/argocd/external-dns/base/values.yaml
   cat ../iac-eks-addons/argocd/cert-manager/base/values.yaml
   ```

2. Read target chart defaults:
   ```bash
   helm show values <repo>/<chart> --version <version> | \
     grep -A5 -E "^(nodeSelector|tolerations|replicas|affinity|podDisruptionBudget|resources|serviceMonitor):"
   ```

3. Check chart structure (DaemonSet vs Deployment):
   ```bash
   helm template <chart> <repo>/<chart> --version <version> | grep "kind: DaemonSet"
   ```

> **Note:** These fields are populated in the intake template but are OPTIONAL
> in deterministic mode. They are MANDATORY research outputs in ai-propose mode.

---

## Version-Lock & Schema Verification Gate (MANDATORY)

> **STOP — Before setting verification booleans to `true`, complete ALL checks below.**
>
> When using `/mobius:add-service`, the command handles chart resolution and
> validation automatically in Phase 1 (Helm Chart Resolution) and Phase 2
> (Research). The steps below document what the command does internally and
> are available for manual use.

This gate prevents deployment failures caused by:
- Assuming chart version or using `latest`
- Using values paths that don't exist in the target chart version
- Mismatched kustomize API versions
- Incorrect image override configuration
- Unreachable or incorrect Helm repo URLs
- Chart names that don't exist in the specified repo

### Step V0: Resolve and Validate Helm Chart Source

**The chart repo URL, chart name, and version must all be verified before proceeding.**

If the user provides only a chart name (no URL):
- Search Artifact Hub, web, or `helm search hub <name>` to find the repo URL
- Present matches and let the user choose

If the user provides a repo URL:
- Validate: `helm repo add <name> <url> && helm repo update`
- If unreachable, stop and ask for the correct URL

If the user provides a version:
- Validate: `helm show chart <name>/<chart> --version <ver>`
- If version not found, list available versions: `helm search repo <name>/<chart> --versions`

**Never proceed with an unverified URL, chart name, or version.**

### Step V1: Verify Exact Chart Version

**Never assume the latest version.** Always verify the exact version exists:

```bash
# Add the Helm repo (if not already added)
helm repo add <repo-name> <helm_repo_url>
helm repo update

# List available versions
helm search repo <repo-name>/<chart-name> --versions | head -20

# Show chart metadata for EXACT version
helm show chart <repo-name>/<chart-name> --version <exact-version>
```

Confirm the output shows:
- `version: <exact-version>` matches your `helm_version`
- `appVersion: <app-version>` is expected

Set `chart_version_verified: true` only after this check passes.

### Step V2: Verify Values Schema for That Version

**Values paths vary between chart versions.** Always verify:

```bash
# Show all values for EXACT version
helm show values <repo-name>/<chart-name> --version <exact-version>

# Pipe to file for reference
helm show values <repo-name>/<chart-name> --version <exact-version> > /tmp/<chart>-values-<version>.yaml
```

Verify:
- All value paths you plan to override exist in this version's schema
- Default values are understood before overriding
- Nested structure matches (e.g., `image.repository` vs `controller.image.repository`)

Set `values_schema_verified: true` only after confirming all value paths.

### Step V3: Verify Image Configuration

If using chart defaults (`image_strategy: default`):
- Confirm the chart's default image is acceptable
- Check the default tag in the values output

If overriding images (`image_strategy: override`):

```bash
# Check the exact values path for image in this chart version
grep -A5 "^image:" /tmp/<chart>-values-<version>.yaml
# Or for nested paths:
grep -A5 "controller:" /tmp/<chart>-values-<version>.yaml | grep -A3 "image:"
```

Verify:
- `image_values_path` matches actual path (e.g., `image.repository`, `controller.image.repository`)
- `image_repository` is a valid registry URL
- `image_tag` is pinned (NOT `latest`) OR `image_digest` is provided
- The image+tag/digest combination exists in the registry

Set `image_version_verified: true` only after confirming image config.

### Step V4: Verify Kustomize API Compatibility

```bash
# Check kustomize version
kustomize version

# Test build with the chart version
mkdir -p /tmp/test-kustomize
cat > /tmp/test-kustomize/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: <chart-name>
    repo: <helm_repo_url>
    version: <exact-version>
    releaseName: <addon>
    namespace: <namespace>
EOF

kustomize build /tmp/test-kustomize --enable-helm
```

Verify:
- Kustomize build succeeds without API deprecation warnings
- Generated manifests use current API versions (not deprecated beta APIs)

Set `kustomize_api_verified: true` only after this check passes.

### Step V5: Verify Health Probes

Inspect the chart's readiness/liveness probe configuration:

```bash
helm show values <repo-name>/<chart-name> --version <exact-version> | grep -A10 "probe"
```

Verify:
- Probes exist (readiness and/or liveness)
- Probe ports match your configuration
- `initialDelaySeconds` accommodates cold-start time (especially with IRSA token fetch)
- `startupProbe` exists if app takes >10s to initialize

If NO probes exist in chart defaults, you MUST add them via `values.yaml` — without
probes, ArgoCD cannot assess pod health and will report Degraded.

Set `probes_health_verified: true` only after this check passes.

### Step V6: Verify ServiceAccount Name Match (if IRSA)

If using IRSA (`aws_resources` includes "irsa"), the chart's ServiceAccount name
must exactly match `xirsarole.spec.serviceAccountName`:

```bash
helm template <chart> <repo>/<chart> --version <ver> | \
  grep -A5 "kind: ServiceAccount" | grep "name:"
```

If these names don't match, IRSA will silently fail — the IAM role is created
but the pod's ServiceAccount never gets the annotation.

Set `sa_name_match_verified: true` only after confirming the names match.

### Step V7: Verify CRD Impact (if chart installs CRDs)

If the chart installs CustomResourceDefinitions:

```bash
helm template <chart> <repo>/<chart> --version <ver> | grep "kind: CustomResourceDefinition"
```

If CRDs are present, verify:
- ApplicationSet uses `ServerSideApply=true` (required for large CRDs)
- ApplicationSet uses `preserveResourcesOnDeletion: true` (prevents cascade deletion)
- CRD upgrades are coordinated with platform team (affects all consumers cluster-wide)

Set `crds_impact_verified: true` only after confirming these safeguards.

### Step V8: Verify XRD Availability (if XRD claims needed)

If `aws_resources` includes "xrd", verify all referenced XRDs are registered:

```bash
# Check iac-eks-crossplane for Configuration CRs
ls ../iac-eks-crossplane/argocd/crossplane/configurations/
```

If a required XRD doesn't exist, **STOP** and run `/mobius:new-xrd` first.

Set `xrd_exists_verified: true` only after confirming all XRDs are available.

### Verification Checklist

| # | Check | Command | Status |
|---|-------|---------|--------|
| V1 | Chart version exists | `helm show chart ... --version X` | [ ] |
| V2 | Values paths valid | `helm show values ... --version X` | [ ] |
| V3 | Image config correct | Check values + registry | [ ] |
| V4 | Kustomize compatible | `kustomize build --enable-helm` | [ ] |
| V5 | Probes verified | `helm show values ... \| grep probe` | [ ] |
| V6 | SA name match (if IRSA) | `helm template ... \| grep ServiceAccount` | [ ] |
| V7 | CRD impact (if CRDs) | Confirm SSA + preserveResources | [ ] |
| V8 | XRD availability (if XRD) | Check `iac-eks-crossplane` Configurations | [ ] |

**All applicable checks must pass before proceeding.**

---

## Chart Characteristics Inspection

> **Run these inspections during Phase 2 (Research) of the `/mobius:add-service`
> command, or manually before generating files.**

After verifying the chart version (V1-V4), inspect these chart characteristics
that affect how ArgoCD manages the addon:

### CRD Detection

```bash
helm template <chart> <repo>/<chart> --version <ver> | grep "kind: CustomResourceDefinition"
```

If CRDs are found:
- ApplicationSet **must** use `ServerSideApply=true` (CRD annotations can exceed size limits)
- ApplicationSet **must** use `preserveResourcesOnDeletion: true` (prevents cascade deletion)
- CRD upgrades affect all consumers cluster-wide — coordinate with platform team

### Helm Hook Detection

```bash
helm template <chart> <repo>/<chart> --version <ver> | grep "helm.sh/hook"
```

If hooks are found:
- ArgoCD runs hooks on **every sync**, not just install
- Charts with hooks may need `hook-delete-policy` or conversion to sync-waves
- Hooks can conflict with explicit sync-wave annotations on XIRSARole claims

### Health Probe Inspection

```bash
helm show values <repo>/<chart> --version <ver> | grep -A10 "probe"
```

Verify:
- Probes exist (readiness and/or liveness) — without probes, ArgoCD cannot
  assess pod health and will report `Degraded`
- Probe ports match your values configuration
- `initialDelaySeconds` accommodates cold-start time (especially IRSA token fetch)
- `startupProbe` exists if app takes >10s to initialize

### ServiceAccount Extraction

```bash
helm template <chart> <repo>/<chart> --version <ver> | grep -A5 "kind: ServiceAccount" | grep "name:"
```

Record the ServiceAccount name — it must match `xirsarole.spec.serviceAccountName`
if using IRSA.

### HPA / Autoscaling Detection

```bash
helm show values <repo>/<chart> --version <ver> | grep -A5 "autoscaling"
```

If HPA is enabled:
- Do NOT set static `replicas` in values.yaml — HPA owns the replica count
- Add `ignoreDifferences` for `spec.replicas` in the ApplicationSet

### Controller-Managed Fields

Some controllers mutate their own resources, causing ArgoCD to show constant
OutOfSync. Known patterns in this platform:

| Pattern | Addons Affected | ignoreDifferences Target |
|---------|----------------|--------------------------|
| IRSA annotation on SA | All IRSA addons | `ServiceAccount` → `metadata.annotations` |
| ExternalSecret fields | grafana, elasticsearch | `ExternalSecret` → controller fields |
| Cilium runtime mutation | cilium | `ConfigMap`, `DaemonSet` |
| Gateway annotations | envoy-gateway | `Gateway` → annotations |
| Crossplane provider spec | crossplane | `Provider` → spec/metadata |

If the addon's controller mutates resources, add `ignoreDifferences` to the
ApplicationSet template. See existing examples in `iac-eks-argocd/applicationsets/`.

---

## Discovery Scope Rule

> **Config files are only discovered if they are in the repo and path pattern
> that the addon's ApplicationSet generator is configured to scan.**

An ApplicationSet generator declares exactly where it looks:

```yaml
generators:
  - git:
      repoURL: https://github.com/boatsgroup/<service-repo>   # which repo
      revision: main
      files:
        - path: "argocd/<addon>/overlays/*/config.yaml"       # which path pattern
```

This means:
- A `config.yaml` placed in a different repo **will never be discovered**, even
  if the path is correct.
- A `config.yaml` placed at a different path in the right repo **will never be
  discovered**, even if the repo is correct.
- Both `generators[].git.repoURL` and `generators[].git.files[].path` must
  match the location of your `config.yaml`.

Real ApplicationSets use a `matrix` generator that combines the git file
generator with a `clusters` selector. The git `repoURL` + `files.path` is still
the definitive discovery scope; the matrix only adds cluster matching.

**Decision before placing config.yaml**:
1. Does an ApplicationSet for this addon already exist?
   - **Yes** → place your `config.yaml` in the repo and path that generator already scans.
     Check: `kubectl get applicationset -n argocd <addon> -o yaml | grep -A6 "generators:"`
   - **No** → choose a service repo, create the ApplicationSet, and set
     `generators[].git.repoURL` and `generators[].git.files[].path` to match.

---

## Inputs Required

Before starting, gather:

| Input | Example | Where to find |
|-------|---------|---------------|
| Intake mode | `deterministic` or `ai-propose` | User preference |
| Addon name (kebab-case) | `cert-manager` | Team requirement |
| Helm chart URL | `https://charts.jetstack.io` | Chart repository |
| Chart name and version | `cert-manager`, `v1.14.5` | **Verified** via `helm show chart` |
| Target environments | `bg-qa`, `bg-prod` | Platform team |
| Namespace | `cert-manager` | Naming convention |
| Namespace strategy | `dedicated` / `shared` / `bootstrap` | See namespace ownership below |
| Service repo for addon configs | `iac-eks-addons` | See Discovery Scope Rule above |
| AWS resources | `none` / `irsa-only` / `irsa-and-xrd` / `xrd-only` | Service requirements |
| Image strategy | `default` or `override` | Deployment requirements |
| Image repository (if override) | `registry.example.com/img` | Private registry URL |
| Image tag or digest (if override) | `v1.14.5` or `sha256:...` | **Pinned, not `latest`** |

> **Critical**: `helm_version` must be an exact, verified version (never `latest`).
> If overriding images, `image_tag` must be pinned or use `image_digest`.

> **Namespace strategy**:
> - `dedicated`: This addon owns the namespace (`CreateNamespace=true`)
> - `shared`: Namespace shared with other addons (`CreateNamespace=false`)
> - `bootstrap`: Must exist before ArgoCD — e.g., `kube-system`, `argocd` (`CreateNamespace=false`)

> **AWS resources**: Use `irsa-only` for IAM roles, `irsa-and-xrd` for IAM + self-service
> resources (S3, SQS), `xrd-only` for resources without IRSA (rare). Shared infrastructure
> (RDS, ElastiCache) belongs in Terraform/Terragrunt, not XRDs.

---

## Repositories / Files Touched

| Repo | Files | Purpose |
|------|-------|---------|
| `<service-repo>` (e.g., `iac-eks-addons`) | `argocd/<addon>/base/kustomization.yaml` | Kustomize base |
| `<service-repo>` | `argocd/<addon>/base/values.yaml` | Default Helm values |
| `<service-repo>` | `argocd/<addon>/overlays/<env>/kustomization.yaml` | Per-env overlay |
| `<service-repo>` | `argocd/<addon>/overlays/<env>/config.yaml` | **ApplicationSet discovery** |
| `<service-repo>` | `argocd/<addon>/overlays/<env>/values.yaml` | Per-env overrides |
| `<service-repo>` | `argocd/<addon>/base/xirsarole.yaml` | IRSA claim base manifest (if AWS) |
| `<service-repo>` | `argocd/<addon>/overlays/<env>/xirsarole-patch.yaml` | Per-env IRSA cluster patch (if AWS) |
| `iac-eks-argocd` | `applicationsets/core-infrastructure/<addon>.yaml` | Multi-source ApplicationSet |
| `iac-eks-argocd` | `applicationsets/core-infrastructure/kustomization.yaml` | Register new ApplicationSet |
| `iac-eks-argocd` | `projects/<project>.yaml` | ArgoCD project permissions |

> **Skill reference**: Per-repo checklists live in
> `iac-eks-addons/.claude/skills/addons-addon/SKILL.md` (structure + config.yaml)
> and `iac-eks-argocd/.claude/skills/argocd-project-guard/SKILL.md` (permissions).

---

## Step-by-Step Procedure

### Step 1 — Resolve cross-repo dependencies

```bash
# In your service repo (e.g., iac-eks-addons)
bash ../mobius-tools/scripts/resolve-deps.sh
```

Verify `iac-eks-argocd` and `iac-eks-crossplane` are available as siblings.

---

### Step 2 — Create the base Kustomize structure

Run this in your service repo:

```bash
mkdir -p argocd/<addon>/base
```

**`argocd/<addon>/base/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
helmCharts:
  - name: <chart-name>
    repo: <chart-url>
    version: <chart-version>
    releaseName: <addon>
    namespace: <namespace>
    valuesFile: values.yaml
```

**`argocd/<addon>/base/values.yaml`**:
```yaml
# Default values — override per environment in overlays/<env>/values.yaml
#
# The /mobius:add-service command generates these blocks automatically
# based on the OPERATIONAL PROFILE confirmed in Phase 3.
#
# When replicas >= 2, the following are REQUIRED:
#   - affinity (soft anti-affinity)
#   - podDisruptionBudget
#   - deploymentStrategy
#
# See Operational Hardening section above for enforcement rules.
```

Validate:
```bash
kustomize build argocd/<addon>/base --enable-helm
# Must exit 0
```

---

### Step 3 — Create environment overlays

Run this in your service repo. Repeat for each target environment (`bg-qa`, `bg-prod`, etc.):

```bash
mkdir -p argocd/<addon>/overlays/<env>
```

**`argocd/<addon>/overlays/<env>/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches: []
```

**`argocd/<addon>/overlays/<env>/values.yaml`**:
```yaml
# Environment-specific overrides
```

**`argocd/<addon>/overlays/<env>/config.yaml`** ← **CRITICAL** (ApplicationSet discovery):
```yaml
addon: "<addon>"
environment: "<env>"           # Must match overlay directory name
enabled: true
testBranch: "main"             # Feature-branch testing; see anti-pattern below

git:
  repoURL: "https://github.com/boatsgroup/<service-repo>"   # THIS repo (where this file lives)
  overlayPath: "argocd/<addon>/overlays/<env>"

helm:
  repoURL: "<chart-url>"
  chart: "<chart-name>"
  version: "<chart-version>"
  releaseName: "<addon>"
  namespace: "<namespace>"

argocd:
  project: "<argocd-project>"
  syncWave: "0"
  prune: true
  selfHeal: true
  allowEmpty: false

labels:
  app.kubernetes.io/part-of: "<team-name>"
```

> **Anti-pattern**: Do NOT put `testBranch` in config.yaml on a feature branch.
> `testBranch` only takes effect when merged to `main`.

> **Note**: The `git.repoURL` in config.yaml must match the ApplicationSet
> generator's `repoURL`. If they differ, values resolution will fail.

Validate overlay builds:
```bash
kustomize build argocd/<addon>/overlays/<env> --enable-helm
# Must exit 0 for every env
```

---

### Step 4 — Add AWS resource claims (if needed)

This step applies when `aws_resources` is anything other than `none`.

#### AWS Resources Decision Tree

| `aws_resources` value | What to do |
|----------------------|------------|
| `none` | Skip this step entirely |
| `irsa-only` | Add XIRSARole claim (most common — see below) |
| `irsa-and-xrd` | Add XIRSARole + additional XRD claims |
| `xrd-only` | Add XRD claims without XIRSARole (rare) |

> **XRD Routing Rule**: XRDs are for 100% self-service resources that teams
> provision via claims. If the addon needs **shared infrastructure** (RDS,
> ElastiCache, VPC peering, shared ALBs), that belongs in Terraform/Terragrunt —
> do NOT create an XRD for shared infrastructure.

> **Missing XRD?** If a required XRD doesn't exist yet, **STOP** and run
> `/mobius:new-xrd` first. Do not proceed until the XRD is registered in
> `iac-eks-crossplane`.

#### Available XRDs (registered in iac-eks-crossplane)

| Kind | XRD Repo | Use Case |
|------|----------|----------|
| `XIRSARole` | `crossplane-xrd-irsa-role` | IAM role for service accounts (IRSA) |
| `XKarpenterNodeRole` | `crossplane-xrd-karpenter-node-role` | IAM role for Karpenter-provisioned nodes |
| `XS3Bucket` | `crossplane-xrd-s3-bucket` | S3 bucket provisioning |
| `XSQSEventBridge` | `crossplane-xrd-sqs-eventbridge` | SQS queue + EventBridge rules |
| `XGatewayNLBListener` | `crossplane-xrd-gateway-nlb-listener` | NLB + TLS for Envoy Gateway |
| `XGeneratedAWSSecret` | `crossplane-xrd-generated-aws-secret` | Credential generation + Secrets Manager |
| `XIngressACMCertificate` | `crossplane-xrd-ingress-acm-certificate` | ACM certificates for ALB Ingress |

#### ServiceAccount name match (CRITICAL for IRSA)

The `serviceAccountName` in the XIRSARole claim **must exactly match** the
ServiceAccount name created by the Helm chart. Verify with:

```bash
helm template <chart> <repo>/<chart> --version <ver> | \
  grep -A5 "kind: ServiceAccount" | grep "name:"
```

If these names don't match, IRSA will silently fail — the IAM role is created
but never used because the pod's ServiceAccount doesn't have the IRSA annotation.

#### Adding an XIRSARole claim

Add the claim directly in `base/` and patch it per environment in each overlay.
There is no separate `infrastructure/` subdirectory.

**`argocd/<addon>/base/xirsarole.yaml`**:
```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XIRSARole
metadata:
  name: <addon>
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  clusterName: placeholder  # Patched per env via overlay
  serviceAccountName: <chart-sa-name>  # MUST match chart's ServiceAccount name
  namespace: <namespace>
  policyArns: []  # Add required managed policy ARNs
```

Add it to `argocd/<addon>/base/kustomization.yaml` under `resources:`:
```yaml
resources:
  - xirsarole.yaml
```

**`argocd/<addon>/overlays/<env>/xirsarole-patch.yaml`** (strategic-merge format):
```yaml
apiVersion: aws.bgrp.io/v1alpha1
kind: XIRSARole
metadata:
  name: <addon>
spec:
  clusterName: <env>
```

Reference the patch from `argocd/<addon>/overlays/<env>/kustomization.yaml`:
```yaml
patches:
  - path: xirsarole-patch.yaml
```

Note: Strategic-merge patches replace matching fields by kind+name. No `target:`
selector needed — the patch itself contains `apiVersion`, `kind`, and
`metadata.name` which identify the target resource.

#### Adding additional XRD claims

For XRD claims beyond XIRSARole (e.g., XS3Bucket, XSQSEventBridge), follow the
same pattern: base manifest at sync-wave `-2`, environment patches in overlays.

See existing examples:
- **XIRSARole + XS3Bucket**: `argocd/policy-reporter/base/` in `iac-eks-addons`
- **XIRSARole + XKarpenterNodeRole + XSQSEventBridge**: `argocd/karpenter/base/` in `iac-eks-addons`

---

### Step 5 — Wire the multi-source ApplicationSet in iac-eks-argocd

> **Pattern choice**: Simple addons (values-only, no IRSA, no kustomization.yaml
> in base) use a **2-source** ApplicationSet. Addons with IRSA claims or overlay
> manifests use a **3-source** ApplicationSet. See both patterns below.

#### Decision point: existing or new ApplicationSet?

**If an ApplicationSet already exists for this addon**:
- Your `config.yaml` must be placed in the repo and path that generator already
  scans. Do not create a duplicate ApplicationSet.
- Skip to Step 6 after confirming your service repo matches the generator.

**If creating a new ApplicationSet**:
- Choose your service repo and set the generator `repoURL` and `files.path`
  to match where your `config.yaml` lives.
- Create the ApplicationSet YAML as shown below.

---

New addons require a dedicated ApplicationSet YAML in
`applicationsets/core-infrastructure/`. The multi-source pattern wires
together the Helm chart, per-environment values, and overlay manifests
(including the `XIRSARole` claim) from the service repo.

Real ApplicationSets use a `matrix` generator combining the git file generator
with a `clusters` selector (see `applicationsets/core-infrastructure/karpenter.yaml`
for a production example). The template below follows that pattern:

**`applicationsets/core-infrastructure/<addon>.yaml`** (three-source pattern):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <addon>
  namespace: argocd
  labels:
    app.kubernetes.io/name: <addon>
    app.kubernetes.io/component: applicationset
    app.kubernetes.io/part-of: core-infrastructure
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  generators:
    - matrix:
        generators:
          # ── Discovery: scans <service-repo> for config.yaml files ──────────
          # This repoURL + files.path is the AUTHORITATIVE discovery scope.
          # config.yaml files placed elsewhere will NOT be discovered.
          - git:
              repoURL: "https://github.com/boatsgroup/<service-repo>"
              revision: main
              files:
                - path: "argocd/<addon>/overlays/*/config.yaml"
          # ── Cluster matching: select clusters by environment label ─────────
          - clusters:
              selector:
                matchLabels:
                  environment: '{{.environment}}'

  template:
    metadata:
      name: "{{.addon}}-{{.environment}}"
      namespace: argocd
      labels:
        app.kubernetes.io/name: "{{.addon}}"
        app.kubernetes.io/part-of: '{{index .labels "app.kubernetes.io/part-of"}}'
        environment: "{{.environment}}"
        managed-by: applicationset
      annotations:
        argocd.argoproj.io/sync-wave: "{{.argocd.syncWave}}"
    spec:
      project: "{{.argocd.project}}"
      sources:
        # Source 0 — Helm chart
        - repoURL: "{{.helm.repoURL}}"
          chart: "{{.helm.chart}}"
          targetRevision: "{{.helm.version}}"
          helm:
            releaseName: "{{.helm.releaseName}}"
            valueFiles:
              - $values/argocd/<addon>/base/values.yaml
              - $values/argocd/<addon>/overlays/{{.environment}}/values.yaml

        # Source 1 — Values ref from service repo (sets $values alias)
        # repoURL must match the generator repoURL above
        - repoURL: "https://github.com/boatsgroup/<service-repo>"
          targetRevision: "{{.testBranch}}"
          ref: values

        # Source 2 — Overlay manifests (XIRSARole, claims, extra resources)
        # repoURL must match the generator repoURL above
        - repoURL: "https://github.com/boatsgroup/<service-repo>"
          targetRevision: "{{.testBranch}}"
          path: "argocd/<addon>/overlays/{{.environment}}"

      destination:
        server: '{{.server}}'
        namespace: "{{.helm.namespace}}"

      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
          - ApplyOutOfSyncOnly=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 5
          backoff:
            duration: 30s
            factor: 2
            maxDuration: 10m

      revisionHistoryLimit: 5

  templatePatch: |
    spec:
      syncPolicy:
        automated:
          prune: {{ .argocd.prune }}
          selfHeal: {{ .argocd.selfHeal }}
          allowEmpty: {{ .argocd.allowEmpty }}

  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update

  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
```

#### Two-Source Pattern (simple addons)

Addons that only need Helm chart values (no kustomization.yaml, no XIRSARole claims,
no overlay manifests) use a simpler two-source pattern. Examples: `cilium`, `kyverno`.

**`applicationsets/core-infrastructure/<addon>.yaml`** (two-source pattern):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <addon>
  namespace: argocd
  labels:
    app.kubernetes.io/name: <addon>
    app.kubernetes.io/component: applicationset
    app.kubernetes.io/part-of: core-infrastructure
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: "https://github.com/boatsgroup/<service-repo>"
              revision: main
              files:
                - path: "argocd/<addon>/overlays/*/config.yaml"
          - clusters:
              selector:
                matchLabels:
                  environment: '{{.environment}}'
  template:
    metadata:
      name: "{{.addon}}-{{.environment}}"
      namespace: argocd
      labels:
        app.kubernetes.io/name: "{{.addon}}"
        app.kubernetes.io/part-of: '{{index .labels "app.kubernetes.io/part-of"}}'
        environment: "{{.environment}}"
        managed-by: applicationset
      annotations:
        argocd.argoproj.io/sync-wave: "{{.argocd.syncWave}}"
    spec:
      project: "{{.argocd.project}}"
      sources:
        # Source 0 — Helm chart with values from service repo
        - repoURL: "{{.helm.repoURL}}"
          chart: "{{.helm.chart}}"
          targetRevision: "{{.helm.version}}"
          helm:
            releaseName: "{{.helm.releaseName}}"
            valueFiles:
              - $values/argocd/<addon>/base/values.yaml
              - $values/argocd/<addon>/overlays/{{.environment}}/values.yaml
        # Source 1 — Values ref from service repo
        - repoURL: "https://github.com/boatsgroup/<service-repo>"
          targetRevision: "{{.testBranch}}"
          ref: values
      destination:
        server: '{{.server}}'
        namespace: "{{.helm.namespace}}"
      syncPolicy:
        syncOptions:
          - CreateNamespace=false
          - ServerSideApply=true
          - ApplyOutOfSyncOnly=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 3
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
      revisionHistoryLimit: 3
  templatePatch: |
    spec:
      syncPolicy:
        automated:
          prune: {{ .argocd.prune }}
          selfHeal: {{ .argocd.selfHeal }}
          allowEmpty: {{ .argocd.allowEmpty }}
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
```

> **When to use 2-source vs 3-source**: Use 2-source when the addon has NO
> kustomization.yaml in base, no XIRSARole claims, and no overlay manifests
> beyond config.yaml and values.yaml. Use 3-source when overlay directories
> contain additional manifests (xirsarole.yaml, patches, etc.) that need
> to be applied as a directory source.

> **Source 1 & 2 consistency**: The `repoURL` in Source 1 and Source 2 must
> match the generator's `repoURL`. All three refer to the same service repo.
> The service repo should usually be your team-owned self-service repo. Use
> `iac-eks-addons` / `iac-eks-observability` only when the addon is part of a
> platform-managed DevOps workflow.

Register the new ApplicationSet in the kustomization list:

**`applicationsets/core-infrastructure/kustomization.yaml`** — add under `resources:`:
```yaml
resources:
  - <addon>.yaml
```

> **Tip**: Verify the file is listed before merging — the ApplicationSet will
> not be picked up by ArgoCD until it appears in `kustomization.yaml`.

---

### Step 6 — Update ArgoCD project permissions

In `iac-eks-argocd`, find the relevant project file:

```bash
ls ../iac-eks-argocd/projects/
```

Add to `sourceRepos` (if chart URL and service repo URL not already present):
```yaml
sourceRepos:
  - "<chart-url>"
  - "https://github.com/boatsgroup/<service-repo>"
```

Add to `destinations` (if namespace not already present):
```yaml
destinations:
  - namespace: "<namespace>"
    server: "*"
```

> **Skill reference**: `iac-eks-argocd/.claude/skills/argocd-project-guard/SKILL.md`
> has the full project update checklist.

---

### Step 7 — Final validation

```bash
# All overlays build successfully (in service repo)
for env in bg-qa bg-prod ops-qa ops-prod; do
  kustomize build argocd/<addon>/overlays/$env --enable-helm 2>/dev/null && \
    echo "✓ $env" || echo "✗ $env FAILED"
done

# config.yaml exists in every overlay
echo "config.yaml count:"
find argocd/<addon>/overlays -name "config.yaml" | wc -l
# Must equal number of overlays created

# ApplicationSet kustomization builds (in iac-eks-argocd)
kustomize build ../iac-eks-argocd/applicationsets/core-infrastructure

# Confirm new ApplicationSet is listed in kustomization resources
grep "<addon>" ../iac-eks-argocd/applicationsets/core-infrastructure/kustomization.yaml
# Must return the <addon>.yaml entry

# Confirm generator repoURL and path match your service repo
kubectl get applicationset -n argocd <addon> -o yaml | grep -A6 "generators:"
# Verify: repoURL == https://github.com/boatsgroup/<service-repo>
# Verify: path    == argocd/<addon>/overlays/*/config.yaml
```

---

## Validation Commands

```bash
# 1. Kustomize build — each overlay (in service repo)
kustomize build argocd/<addon>/overlays/<env> --enable-helm

# 2. config.yaml present in all overlays
find argocd/<addon>/overlays -name "config.yaml"

# 3. ApplicationSet kustomization builds (in iac-eks-argocd)
kustomize build ../iac-eks-argocd/applicationsets/core-infrastructure

# 4. New ApplicationSet is registered in kustomization
grep "<addon>" ../iac-eks-argocd/applicationsets/core-infrastructure/kustomization.yaml

# 5. Generator repoURL and path point to the correct service repo
kubectl get applicationset -n argocd <addon> -o yaml | grep -A6 "generators:"
# Expected output includes:
#   repoURL: https://github.com/boatsgroup/<service-repo>
#   path: argocd/<addon>/overlays/*/config.yaml

# 6. After merge to main — ApplicationSet discovered new Application
kubectl -n argocd get applications | grep <addon>

# 7. After sync — addon running
kubectl -n <namespace> get pods
```

---

## Failure Modes

| Symptom | Cause | Where to look | Fix |
|---------|-------|---------------|-----|
| No Application generated | Missing `config.yaml` | `find argocd/<addon>/overlays -name config.yaml` | Create config.yaml in every overlay |
| No Application generated | config.yaml in wrong repo | `kubectl get applicationset -n argocd <addon> -o yaml \| grep repoURL` | Move config.yaml to the repo the generator scans |
| No Application generated | config.yaml at wrong path | `kubectl get applicationset -n argocd <addon> -o yaml \| grep path` | Fix path to match `argocd/<addon>/overlays/*/config.yaml` |
| Application created but sync fails | Project missing source/dest | `kubectl get appproject -n argocd <project> -o yaml` | Add to `sourceRepos` + `destinations` |
| `kustomize build` fails | Bad kustomization.yaml | Error output | Fix dangling references |
| IRSA claim stuck | clusterName not patched | `kubectl get xirsarole -A` | Add/fix `xirsarole-patch.yaml` in each overlay |
| testBranch not working | On feature branch | Check git branch | Must be merged to main |

> See also: `docs/troubleshooting.md#7-kustomize--argocd-issues` for ArgoCD-level issues.

---

## Merge Order

This workflow touches two repos. Merge in this order to avoid broken states:

1. **`iac-eks-argocd`** — merge project permission changes first
   - ArgoCD can't sync the addon if permissions aren't set yet
2. **`<service-repo>`** (e.g., `iac-eks-addons`) — merge the addon base/overlay/config.yaml
   - ApplicationSet discovers config.yaml and creates the Application

> **Why this order?** If you merge the service repo first, ArgoCD creates an
> Application but immediately fails sync with a permissions error. Merging
> `iac-eks-argocd` first means the permission exists before the Application appears.

---

## Git Workflow (Integrated)

When using `/mobius:add-service`, the command handles the full git workflow
automatically:

- **Phase 1 preflight**: Verifies `gh auth status`, clean working tree, and
  current branch. If not on `main`, asks whether to use the current branch
  or switch to `main` and create a new one. Prompts for a JIRA ticket.
- **Phase 3.5 branch gate**: Creates feature branches in all affected repos
  before any files are generated. No changes land on `main`.
- **Phase 6 commit/push/PR**: Commits changes (one commit per repo), pushes,
  and creates PRs sequentially (`iac-eks-argocd` first to capture the URL,
  then the service repo PR references it with merge order).

For manual execution without the command, follow
`docs/workflows/shared/multi-repo-git-workflow.md` for the full pattern and
`docs/workflows/shared/jira-integration.md` for JIRA ticket setup.
