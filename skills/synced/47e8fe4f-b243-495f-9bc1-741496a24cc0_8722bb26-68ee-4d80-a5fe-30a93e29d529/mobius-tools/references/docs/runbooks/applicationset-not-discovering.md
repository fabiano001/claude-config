# Runbook: ApplicationSet Not Discovering Services

## Symptoms

- `config.yaml` merged to `main` but no ArgoCD Application was created
- ApplicationSet exists but generates 0 applications (or fewer than expected)
- New environment overlay added but ArgoCD doesn't pick it up
- Application was previously working but disappeared after ApplicationSet change

## Quick Triage (under 2 minutes)

```bash
# 1. Does the ApplicationSet exist and is it applied?
kubectl get applicationset -n argocd | grep <appset-name>

# 2. How many applications does it currently generate?
kubectl get applicationset -n argocd <appset-name> -o json | \
  jq '.status.conditions'

# 3. What's the generator looking for?
kubectl get applicationset -n argocd <appset-name> -o json | jq '{
  repoURL: .spec.generators[].git.repoURL,
  revision: .spec.generators[].git.revision,
  filePattern: .spec.generators[].git.files[].path
}'
```

## How ApplicationSet Discovery Works

```
ApplicationSet (in iac-eks-argocd)
  ├── Generator: git file generator
  │     reads: <service-repo>/argocd/*/overlays/*/config.yaml
  │     on branch: main (or HEAD)
  │
  └── Template: creates an ArgoCD Application for each config.yaml found
        using values from config.yaml (repoURL, path, project, chart, etc.)
```

The generator scans the source repo on a polling interval (~3 minutes).
If `config.yaml` doesn't match the file pattern, it's invisible.

## Common Causes and Fixes

### 1. config.yaml not on `main` branch

The generator reads from `main` (or the configured revision). If `config.yaml`
only exists on a feature branch, the ApplicationSet won't see it.

**Check:**
```bash
# What branch does the generator read?
kubectl get applicationset -n argocd <appset-name> -o json | \
  jq '.spec.generators[].git.revision'

# Does config.yaml exist on that branch?
git ls-remote origin main  # get the SHA
git show origin/main:argocd/<service>/overlays/<env>/config.yaml
```

**Fix:** Merge the PR containing `config.yaml` to `main`.

### 2. config.yaml path doesn't match generator file pattern

**Check:**
```bash
# Generator expects this pattern:
kubectl get applicationset -n argocd <appset-name> -o json | \
  jq '.spec.generators[].git.files[].path'
# e.g., "argocd/*/overlays/*/config.yaml"

# Actual file path:
ls <service-repo>/argocd/<service>/overlays/<env>/config.yaml
```

Common mismatches:
- Extra nesting level (e.g., `argocd/team/service/...` vs `argocd/service/...`)
- Wrong directory name (`addons/` vs `argocd/`)
- Missing `overlays/` level

**Fix (permanent):** Either move the `config.yaml` to match the pattern,
or update the ApplicationSet's file pattern in `iac-eks-argocd`.

### 3. config.yaml has invalid YAML or missing required fields

**Check:**
```bash
# Validate YAML syntax
cat <service-repo>/argocd/<service>/overlays/<env>/config.yaml | python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)"

# Check required fields
cat <service-repo>/argocd/<service>/overlays/<env>/config.yaml
```

Required fields typically include:
- `repoURL` — the service repo's Git URL
- `overlayPath` — path to the Kustomize overlay
- `argocd.project` — which ArgoCD project to use
- For Helm: `helm.repoURL`, `helm.chart`, `helm.version`

**Fix:** Correct the `config.yaml` content and merge to `main`.

### 4. ApplicationSet YAML not registered in kustomization.yaml

The ApplicationSet YAML file exists in `iac-eks-argocd` but isn't referenced
by the kustomization.yaml, so ArgoCD never applies it.

**Check:**
```bash
# Does the kustomization include the ApplicationSet?
cat ../iac-eks-argocd/applicationsets/<group>/kustomization.yaml | grep <appset-file>
```

**Fix (permanent):** Add the ApplicationSet YAML to the `resources:` list
in `iac-eks-argocd/applicationsets/<group>/kustomization.yaml`.

### 5. Generator repoURL doesn't match actual repo

**Check:**
```bash
# Generator source repo
kubectl get applicationset -n argocd <appset-name> -o json | \
  jq '.spec.generators[].git.repoURL'

# Compare to the actual service repo URL
git -C <service-repo> remote get-url origin
```

**Fix:** Update either the generator's `repoURL` (in `iac-eks-argocd`) or the
repo's remote URL to match.

### 6. ArgoCD project doesn't permit the service repo

Even if the ApplicationSet finds `config.yaml` and creates an Application,
the Application will fail to sync if the ArgoCD project doesn't allow the source repo.

**Check:**
```bash
kubectl get appproject -n argocd <project-name> -o json | jq '.spec.sourceRepos'
```

**Fix (permanent):** Add the repo URL to `spec.sourceRepos` in
`iac-eks-argocd/projects/<team>/<project>/project.yaml`.

### 7. ApplicationSet controller not running

**Check:**
```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50
```

If the controller is down, no ApplicationSets will be reconciled.

## Cross-Repo Verification

The full discovery chain spans 3 repos. Verify all links:

```bash
# 1. Service repo: config.yaml exists and is valid
cat <service-repo>/argocd/<service>/overlays/<env>/config.yaml

# 2. iac-eks-argocd: ApplicationSet references the service repo
cat ../iac-eks-argocd/applicationsets/<group>/<appset>.yaml

# 3. iac-eks-argocd: ApplicationSet is registered in kustomization
cat ../iac-eks-argocd/applicationsets/<group>/kustomization.yaml

# 4. iac-eks-argocd: Project permits the service repo
cat ../iac-eks-argocd/projects/<team>/<project>/project.yaml
```

## Post-Resolution

1. Wait 3-5 minutes for the generator to poll (or force a refresh)
2. Verify: `kubectl get applicationset -n argocd <appset-name> -o json | jq '.status'`
3. Verify: `argocd app list | grep <service>`
4. Run `/mobius:validate-service` to confirm the generated Application is healthy
