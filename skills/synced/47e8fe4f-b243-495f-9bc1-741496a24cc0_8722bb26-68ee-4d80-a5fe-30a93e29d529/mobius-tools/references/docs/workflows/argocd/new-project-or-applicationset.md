# Workflow: Adding a New ArgoCD Project or ApplicationSet

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order; each step includes a
> verification command.

---

## Purpose

Adds a new ArgoCD Project (for access control) or a new ApplicationSet (for
multi-cluster application templating) to the hub control plane in `iac-eks-argocd`.

Use this workflow when:
- A new team or service needs its own ArgoCD Project with scoped permissions
- A new class of addons requires a new ApplicationSet with Git File Generator
- An existing ApplicationSet needs to be extended to cover a new repo or pattern

---

## Inputs Required

| Input | Example | Where to find |
|-------|---------|---------------|
| Project name | `platform-addons` | Team convention |
| Source repo URLs | `https://github.com/boatsgroup/iac-eks-addons` | Addon repos |
| Destination namespaces | `cert-manager`, `external-dns` | Addon requirements |
| Cluster server | `*` (all) or specific URL | Cluster list |
| ApplicationSet name | `core-addons` | Team convention |
| Generator path pattern | `argocd/*/overlays/*/config.yaml` | Addon overlay pattern |

---

## Repositories / Files Touched

### For a new Project

| Repo | Files | Purpose |
|------|-------|---------|
| `iac-eks-argocd` | `projects/<team>/<project-name>/project.yaml` | Project definition |
| `iac-eks-argocd` | `projects/<team>/<project-name>/kustomization.yaml` | Project kustomization |
| `iac-eks-argocd` | `projects/<team>/kustomization.yaml` | Team kustomization (if new team) |
| `iac-eks-argocd` | `projects/kustomization.yaml` | Root kustomization (if new team) |

### For a new ApplicationSet

| Repo | Files | Purpose |
|------|-------|---------|
| `iac-eks-argocd` | `applicationsets/<group>/<appset-name>.yaml` | ApplicationSet definition |
| `iac-eks-argocd` | `applicationsets/<group>/kustomization.yaml` | Register with kustomize |

> **Skill reference**: `iac-eks-argocd/.claude/skills/argocd-project-guard/SKILL.md`
> has the project permission enforcement checklist.
> `iac-eks-argocd/.claude/skills/argocd-applicationset-wiring/SKILL.md`
> has the ApplicationSet discovery verification checklist.

---

## Section A: Adding a New ArgoCD Project

### Step A1 — Create the project definition

```bash
# In iac-eks-argocd
mkdir -p projects/<team>/<project-name>
```

**`projects/<team>/<project-name>/project.yaml`**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: <project-name>
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: "<Human-readable description>"
  sourceRepos:
    - "https://github.com/boatsgroup/<source-repo>"
    # Add one entry per repo that Applications in this project will sync from
  destinations:
    # In-cluster (hub)
    - namespace: "<namespace>"
      server: https://kubernetes.default.svc
    # Spoke clusters (add one per namespace per spoke)
    - namespace: "<namespace>"
      server: "<spoke-cluster-api-server-url>"
    # Get spoke API server URLs from existing project files or:
    # kubectl config get-contexts
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
    # Add additional cluster-scoped resource types as needed
    # (e.g., CRDs for Crossplane, RBAC for cluster roles)
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
```

> **Common mistake**: Forgetting to add new Helm chart repos to `sourceRepos`.
> ArgoCD will reject the sync with "repository not permitted".

---

### Step A2 — Register in kustomization hierarchy

Project registration uses a 3-level kustomization hierarchy.

**1. Create `projects/<team>/<project-name>/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - project.yaml
```

**2. If the team directory is NEW, create `projects/<team>/kustomization.yaml`**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - <project-name>/
```

**3. If the team directory is NEW, add it to `projects/kustomization.yaml`**:
```yaml
resources:
  - default/
  - devops/
  - devsecops/
  - <team>/    # ← add new team here
```

**4. If adding a project to an EXISTING team, just add to `projects/<team>/kustomization.yaml`**:
```yaml
resources:
  - core-infrastructure/
  - monitoring/
  - <project-name>/    # ← add here
```

> **New team onboarding**: When adding a brand new team (not just a project),
> you must:
> 1. Create `projects/<team>/kustomization.yaml` with initial project references
> 2. Add `<team>/` to `projects/kustomization.yaml`
>
> Existing teams: `default`, `devops`, `devsecops`

---

### Step A3 — Validate

```bash
# Build kustomize output (must exit 0)
kustomize build projects/

# Apply dry-run to cluster
kubectl apply -f projects/<project-name>.yaml --dry-run=server -n argocd

# After merge — verify project exists
kubectl get appproject -n argocd <project-name>
```

---

## Section B: Adding a New ApplicationSet

### Step B1 — Choose the generator type

The Mobius platform uses **Git File Generator** exclusively for self-service
addons. It discovers config.yaml files and creates one Application per file.

```
Matrix Generator pattern (git + clusters):
  Git: Discovers config.yaml files at argocd/<addon>/overlays/*/config.yaml
  Clusters: Selects clusters using matchLabels (environment, region, hub)
  Result: One Application per config.yaml + matching cluster combination
```

> **Cluster label matching**: Bootstrap applies labels (`environment`, `region`,
> `hub`) to cluster secrets. The `clusters:` generator uses `matchLabels` to
> select which clusters an ApplicationSet deploys to. For example,
> `environment: '{{.environment}}'` matches clusters where the environment
> label equals the environment from the config.yaml path.

### Step B2 — Create the ApplicationSet

```bash
mkdir -p applicationsets/<group>
touch applicationsets/<group>/<appset-name>.yaml
```

**`applicationsets/<group>/<appset-name>.yaml`**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <appset-name>
  namespace: argocd
  labels:
    app.kubernetes.io/name: <appset-name>
    app.kubernetes.io/component: applicationset
    app.kubernetes.io/part-of: <group>
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: "https://github.com/boatsgroup/<source-repo>"
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
      project: "<project-name>"
      sources:
        - repoURL: "{{.helm.repoURL}}"
          chart: "{{.helm.chart}}"
          targetRevision: "{{.helm.version}}"
          helm:
            releaseName: "{{.helm.releaseName}}"
            valueFiles:
              - $values/argocd/<addon>/base/values.yaml
              - $values/argocd/<addon>/overlays/{{.environment}}/values.yaml
        - repoURL: "https://github.com/boatsgroup/<source-repo>"
          targetRevision: "{{.testBranch}}"
          ref: values
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

> **Anti-pattern**: Do NOT use `force: true` in syncPolicy — this can cause
> data loss on conflicting resources.

---

### Step B3 — Register with kustomization

**1. Add the ApplicationSet to the group's kustomization**:

Add to **`applicationsets/<group>/kustomization.yaml`**:
```yaml
resources:
  - # ... existing entries
  - <appset-name>.yaml
```

**2. If the group is NEW, wire it into env-level kustomization**:

Each environment only includes the ApplicationSet groups it needs. Edit the
env-level kustomization at:
`hubs/<hub>/environments/<hub>/<region>/applicationsets/kustomization.yaml`

```yaml
resources:
  - ../../../../../applicationsets/core-infrastructure/
  - ../../../../../applicationsets/<group>/    # ← add new group here
```

> **Note**: For example, `bg-dev` only includes `core-infrastructure`, while
> `bg-qa` includes `api-node`. There is NO root `applicationsets/kustomization.yaml`.

---

### Step B4 — Validate

```bash
# Build the applicationsets layer (must exit 0)
kustomize build applicationsets/<group>/

# Check for YAML parse errors
kubectl apply -f applicationsets/<group>/<appset-name>.yaml --dry-run=server -n argocd

# After merge — ApplicationSet exists
kubectl get applicationset -n argocd <appset-name>

# After ApplicationSet discovers config.yaml files — Applications appear
kubectl get applications -n argocd | grep <cluster>-<addon>
```

---

## Validation Commands

```bash
# 1. Kustomize builds clean
kustomize build projects/
kustomize build applicationsets/<group>/

# 2. Dry-run applies cleanly
kubectl apply -f projects/<project-name>.yaml --dry-run=server -n argocd
kubectl apply -f applicationsets/<group>/<appset-name>.yaml --dry-run=server -n argocd

# 3. ArgoCD controller accepts the resources (after sync)
kubectl get appproject -n argocd <project-name> -o jsonpath='{.status}'
kubectl get applicationset -n argocd <appset-name> -o jsonpath='{.status}'

# 4. Applications generated (after addon config.yaml exists)
kubectl get applications -n argocd | grep <appset-name>
```

---

## Failure Modes

| Symptom | Cause | Where to look | Fix |
|---------|-------|---------------|-----|
| Application sync: "repository not permitted" | Source repo missing from project | `kubectl get appproject -n argocd <project> -o yaml` | Add to `sourceRepos` |
| Application sync: "namespace not permitted" | Destination namespace missing | Same as above | Add to `destinations` |
| ApplicationSet creates no Applications | config.yaml not matching path pattern | `kubectl describe applicationset -n argocd <name>` | Verify generator path; check config.yaml exists |
| ApplicationSet error: "missing key" | config.yaml missing expected field | ApplicationSet events | Add required field to config.yaml template or make optional |
| Applications created but sync immediately fails | `force: true` removed needed resource | ArgoCD Application events | Remove `force: true` |
| Project finalizer blocks deletion | Finalizer on AppProject | `kubectl get appproject` | Manually remove finalizer if safe |

---

## Merge Order

For a new project + new ApplicationSet in the same change:

1. **`iac-eks-argocd`** — merge project and ApplicationSet in a single PR
   - Merge project first if it's a separate PR, then ApplicationSet
   - ArgoCD syncs automatically once merged to main
2. **`iac-eks-addons`** (or source repo) — merge config.yaml files
   - ApplicationSet discovers them and creates Applications

> **Why this order?** The ApplicationSet references a project by name. If the
> project doesn't exist when the ApplicationSet syncs, the Application creation
> will fail with "project not found".

---

## Bootstrap Dependency

> **Bootstrap dependency**: The `argocd-projects` Application (sync-wave `-10`)
> in `bootstrap/base/app-of-apps/argocd-projects-application.yaml` manages
> the `projects/` directory. New project files are automatically synced to ArgoCD
> when merged to main. No manual Application creation needed.
