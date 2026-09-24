# Workflow: Creating a New Crossplane XRD

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order; each step includes a
> verification command.

---

## Purpose

Creates a new KCL-based Crossplane XRD (Composite Resource Definition) as a
standalone repo, packages it as an OCI configuration, and registers it with
the platform so claims can be created in EKS clusters.

**When to use this workflow**:
- A new type of AWS resource needs to be provisioned via Crossplane claims
- An existing XRD needs to be replaced with a new one (new repo)
- Expanding the platform's self-service surface area

> **Important**: All new XRDs use the KCL + OCI Configuration pattern.
> Do NOT use inline Go-templated compositions in `iac-eks-crossplane` —
> that is a legacy pattern and must not be extended.

---

## Inputs Required

| Input | Example | Where to find |
|-------|---------|---------------|
| Resource name (kebab-case) | `rds-cluster` | Team requirement |
| AWS resource type | `RDS Cluster` | Team requirement |
| API group | `aws.platform.boatsgroup.com` | Platform standard |
| API version | `v1alpha1` | Start here, bump as API matures |
| KCL module name | `crossplane-xrd-rds-cluster` | `crossplane-xrd-{resource-name}` |
| XRD group/kind | `XRDsCluster` | PascalCase of resource name |

---

## Repositories / Files Touched

| Repo | Files | Purpose |
|------|-------|---------|
| `crossplane-xrd-<name>` (new repo) | `kcl/main.k`, `kcl/config.k`, `kcl/helpers.k` | KCL composition logic |
| `crossplane-xrd-<name>` | `kcl/kcl.mod` | KCL module definition |
| `crossplane-xrd-<name>` | `crossplane.yaml` | Package metadata |
| `crossplane-xrd-<name>` | `composition.yaml` | Crossplane Composition CR |
| `crossplane-xrd-<name>` | `definition.yaml` | CompositeResourceDefinition CR |
| `crossplane-xrd-<name>` | `functions.yaml` | Function references for local testing |
| `crossplane-xrd-<name>` | `test/basic-params.json` | Local test parameters |
| `iac-eks-crossplane` | `argocd/crossplane/base/configurations/<name>.yaml` | Configuration CR |
| `iac-eks-crossplane` | `argocd/crossplane/base/configurations/kustomization.yaml` | Register with kustomize |
| `iac-eks-crossplane` | `argocd/crossplane/overlays/<env>/configurations/<name>-patch.yaml` | Per-env version pin |
| `mobius-tools` | `ecosystem/dependency-graph.yaml` | Add new repo to graph |

> **Skill reference**: `iac-eks-crossplane/.claude/skills/crossplane-configuration/SKILL.md`
> covers Configuration CR sync-wave ordering and checklist.

---

## Step-by-Step Procedure

### Step 1 — Create the new repo from template

Use `crossplane-xrd-irsa-role` as the reference implementation:

```bash
# Create the new repo on GitHub
gh repo create boatsgroup/crossplane-xrd-<name> \
  --private \
  --description "Crossplane XRD: <Resource Name>"

# Clone it locally
gh repo clone boatsgroup/crossplane-xrd-<name> ../crossplane-xrd-<name>
cd ../crossplane-xrd-<name>
```

Copy the skeleton structure from the reference repo:
```bash
cp -r ../crossplane-xrd-irsa-role/kcl ./kcl
cp ../crossplane-xrd-irsa-role/definition.yaml .
cp ../crossplane-xrd-irsa-role/crossplane.yaml .
cp ../crossplane-xrd-irsa-role/functions.yaml .
```

---

### Step 2 — Define the XRD

**`definition.yaml`** — the CompositeResourceDefinition:
```yaml
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: x<resourcename>s.<api-group>
  labels:
    app.kubernetes.io/name: <name>-composition
    app.kubernetes.io/part-of: crossplane-compositions
    version: v1alpha1
spec:
  defaultCompositionRef:
    name: <name>-v1alpha1
  group: <api-group>
  # MUST be cluster-scoped for AWS resources (Crossplane v2 requirement)
  scope: Cluster
  names:
    kind: X<ResourceName>
    plural: x<resourcename>s
    singular: x<resourcename>
    categories:
      - crossplane
      - composition
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                # Add your parameters here
```

> **Anti-pattern**: Do NOT use `scope: Namespaced` for AWS resources.
> Crossplane v2 requires cluster-scoped XRDs for cloud resources.
> Do NOT include `claimNames:` — Crossplane v2 cluster-scoped XRDs don't use claims in definition.yaml.

---

### Step 3 — Write the KCL composition

All `.k` files in `kcl/` share a flat namespace — do NOT use explicit imports.

**`kcl/config.k`** — parameter schema:
```python
# Read Composite Resource
oxr = option("params").oxr
spec = oxr.spec

# Required fields (from XRD spec)
cluster_name = spec.clusterName or ""
# Add your parameters from spec here
```

**`kcl/helpers.k`** — helper functions:
```python
# Shared helper functions
# Reference directly — no import needed
```

**`kcl/main.k`** — composition logic:
```python
# No import statements — flat-file KCL pattern
# All .k files in kcl/ share a namespace automatically

# Combine all resources into output
items = [
    # Compose managed resources here
]
```

> **Anti-pattern**: Do NOT add `import config` or `import helpers` to `main.k`.
> KCL flat-file pattern: all `.k` files in the same directory share a namespace.

---

### Step 4 — Write Crossplane manifests

**`composition.yaml`**:
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: <name>-v1alpha1
  labels:
    provider: aws
    crossplane.io/xrd: x<resourcename>s.<api-group>
spec:
  compositeTypeRef:
    apiVersion: <api-group>/v1alpha1
    kind: X<ResourceName>
  mode: Pipeline
  pipeline:
    - step: generate-resources
      functionRef:
        name: function-kcl
      input:
        apiVersion: krm.kcl.dev/v1alpha1
        kind: KCLInput
        spec:
          source: oci://boatsgroup.pe.jfrog.io/bg-crossplane/kcl-<name>:v0.0.1
```

**`crossplane.yaml`** — package metadata:
```yaml
apiVersion: meta.pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: crossplane-xrd-<name>
  annotations:
    meta.crossplane.io/maintainer: platform-team@boatsgroup.com
    meta.crossplane.io/source: github.com/boatsgroup/crossplane-xrd-<name>
spec:
  crossplane:
    version: ">=v2.0.0"
  # REQUIRED: prevents Crossplane from fighting ArgoCD over function deps
  skipDependencyResolution: true
  dependsOn: []
```

---

### Step 5 — Test locally

```bash
cd kcl
kcl run . -S items -D "params=$(cat ../test/basic-params.json)"
# Must produce valid Kubernetes manifests (no Python errors)
```

```bash
# Full render with functions
crossplane beta render examples/claim.yaml composition.yaml functions.yaml
# Must produce rendered composed resources
```

---

### Step 6 — Tag and publish the OCI package

Once the KCL and composition logic is correct:

```bash
# Push code to main
git add . && git commit -m "feat: initial XRD implementation"
git push origin main

# Create a version tag — GitHub Actions publishes to JFrog OCI
git tag v0.0.1
git push origin v0.0.1
```

> **CI publishes TWO OCI artifacts**:
> 1. `kcl-<name>` — the KCL module (referenced by composition.yaml)
> 2. `crossplane-xrd-<name>` — the Configuration package (deployed via iac-eks-crossplane)
>
> The GitHub Actions release workflow also:
> - Auto-updates `kcl/kcl.mod` version
> - Auto-updates `composition.yaml` KCL source reference
>
> **Never manually edit** `kcl/kcl.mod` or `composition.yaml` version references — CI handles this.

Verify the package was published:
```bash
# Check JFrog OCI registry (requires jfrog CLI or crane)
crane ls boatsgroup.pe.jfrog.io/bg-crossplane/crossplane-xrd-<name>
# Should show: v0.0.1
```

---

### Step 7 — Register with iac-eks-crossplane

In `iac-eks-crossplane`, add the Configuration CR:

**`argocd/crossplane/base/configurations/<name>.yaml`**:
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: crossplane-xrd-<name>
  labels:
    app.kubernetes.io/name: crossplane-xrd-<name>
    app.kubernetes.io/part-of: crossplane
    app.kubernetes.io/managed-by: argocd
spec:
  package: boatsgroup.pe.jfrog.io/bg-crossplane/crossplane-xrd-<name>:v0.0.1
  skipDependencyResolution: true
  revisionActivationPolicy: Automatic
  revisionHistoryLimit: 3
```

> **Note**: The sync-wave annotation is applied automatically by `argocd/crossplane/base/configurations/kustomization.yaml` via `commonAnnotations` (currently wave `5`), not per-resource.

Add it to **`argocd/crossplane/base/configurations/kustomization.yaml`**:
```yaml
resources:
  - # ... existing entries
  - <name>.yaml
```

Create per-environment version patches in each overlay:
**`argocd/crossplane/overlays/<env>/configurations/<name>-patch.yaml`**:
```yaml
apiVersion: pkg.crossplane.io/v1
kind: Configuration
metadata:
  name: crossplane-xrd-<name>
spec:
  package: boatsgroup.pe.jfrog.io/bg-crossplane/crossplane-xrd-<name>:v0.0.1
```

> **Note**: Also add the patch file to each overlay's `kustomization.yaml` under `patches:` or `patchesStrategicMerge:`.

Validate:
```bash
kustomize build argocd/crossplane/overlays/<env>
# Must exit 0
```

---

### Step 8 — Update the dependency graph

In `mobius-tools`, add the new repo to the ecosystem:

**`ecosystem/dependency-graph.yaml`** — add entry under the `repos:` key:
```yaml
# In mobius-tools/ecosystem/dependency-graph.yaml, under the 'repos:' key:
  crossplane-xrd-<name>:
    role: "<Resource Name> XRD — KCL composition for <brief description>"
    tier: xrd
    github: "boatsgroup/crossplane-xrd-<name>"
    key_docs:
      - CLAUDE.md
      - .claude/ecosystem.md
      - definition.yaml
      - kcl/main.k
    dependencies:
      - iac-eks-crossplane
```

---

### Step 9 — Add AGENTS.md to the new repo

Copy the frontmatter template:
```bash
cp ../mobius-tools/templates/agents-frontmatter.md ../crossplane-xrd-<name>/AGENTS.md
```

Edit to fill in the new repo's details:
```yaml
---
mobius:
  repo: crossplane-xrd-<name>
  org: boatsgroup
  dependencies: []
---
```

---

## Validation Commands

```bash
# 1. KCL renders without errors
cd kcl && kcl run . -S items -D "params=$(cat ../test/basic-params.json)"

# 2. Full crossplane render
crossplane beta render examples/claim.yaml composition.yaml functions.yaml

# 3. OCI package published
crane ls boatsgroup.pe.jfrog.io/bg-crossplane/crossplane-xrd-<name>

# 4. Configuration CR registered
kubectl get configuration crossplane-xrd-<name>

# 5. XRD is established
kubectl get xrd x<resourcename>s.<api-group>

# 6. Test claim renders
kubectl apply -f examples/claim.yaml --dry-run=server
```

---

## Failure Modes

| Symptom | Cause | Where to look | Fix |
|---------|-------|---------------|-----|
| KCL import error | `import helpers` in main.k | `kcl/main.k` | Remove all import statements |
| Configuration stuck `Installing` | Missing `skipDependencyResolution: true` | `crossplane.yaml` or Configuration CR | Add the field |
| Configuration stuck `Installing` | OCI package not published | `crane ls ...` | Tag the repo, wait for CI |
| XRD not created | Configuration not registered | `kubectl get configuration` | Add to iac-eks-crossplane |
| Claim `Unresolvable` | Composition not found | `kubectl describe composite ...` | Verify composition labels match XRD |
| Version mismatch | Configuration CR version ≠ KCL tag | Configuration CR spec | Align versions |

> See also: `docs/troubleshooting.md#6-xrd--crossplane-issues` for more detail.

---

## Merge Order

This workflow creates one new repo and modifies two existing repos:

1. **Create and push `crossplane-xrd-<name>`** — push main + tag `v0.0.1`
   - GitHub Actions publishes the OCI package
   - Must be done before the Configuration CR points at it
2. **`iac-eks-crossplane`** — merge the Configuration CR registration
   - ArgoCD syncs the Configuration, Crossplane pulls the OCI package
   - XRD becomes available to the cluster
3. **`mobius-tools`** — merge dependency-graph.yaml update
   - No operational impact; keeps the ecosystem graph accurate

> **Why this order?** ArgoCD will try to pull the OCI image as soon as the
> Configuration CR is synced. If the tag doesn't exist yet, the Configuration
> will be stuck in `Installing`. Always push the tag and wait for CI before
> merging the iac-eks-crossplane change.
