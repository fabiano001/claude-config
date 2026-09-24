# Runbook: ArgoCD Sync Stuck or Failed

## Symptoms

- ArgoCD Application shows `OutOfSync` and won't sync
- Sync status is `SyncFailed` with an error message
- Sync hangs indefinitely (spinner never completes)
- Application is stuck in `Terminating` state

## Quick Triage (under 2 minutes)

```bash
# 1. Check application status
argocd app get <app-name>

# 2. Check sync history for recent errors
argocd app history <app-name>

# 3. Check which resources are unhealthy
argocd app get <app-name> -o json | jq -r '.status.resources[] |
  select(.health.status != "Healthy" or .status != "Synced") |
  "\(.kind)/\(.name) → sync=\(.status) health=\(.health.status)"'
```

## Common Causes and Fixes

### 1. Repo access denied

**Error:** `rpc error: code = Unknown desc = error creating SSH agent`
or `repository not accessible`

**Check:**
```bash
# Verify ArgoCD can reach the repo
argocd repo list | grep <repo-url>
```

**Fix:** The repo isn't registered in ArgoCD or the deploy key expired.
- Verify repo registration in `iac-eks-argocd/repositories/`
- Check GitHub deploy key is still valid

### 2. Namespace not permitted by project

**Error:** `application destination {namespace} is not permitted in project`

**Check:**
```bash
kubectl get appproject -n argocd <project-name> -o json | jq '.spec.destinations'
```

**Fix (permanent):**
- Edit `iac-eks-argocd/projects/<team>/<project>/project.yaml`
- Add the target namespace to `spec.destinations`
- Merge and let ArgoCD sync the project change first

### 3. Source repo not permitted by project

**Error:** `application repo <url> is not permitted in project`

**Check:**
```bash
kubectl get appproject -n argocd <project-name> -o json | jq '.spec.sourceRepos'
```

**Fix (permanent):**
- Edit `iac-eks-argocd/projects/<team>/<project>/project.yaml`
- Add the repo URL to `spec.sourceRepos`

### 4. Helm chart not found or version mismatch

**Error:** `chart not found` or `version not found in repository`

**Check:**
```bash
# What chart/version does the app expect?
argocd app get <app-name> -o json | jq '{
  chart: .spec.source.chart,
  version: .spec.source.targetRevision,
  repoURL: .spec.source.repoURL
}'
```

**Fix (permanent):**
- Update `config.yaml` in the service repo overlay: fix `helm.chart`, `helm.version`, or `helm.repoURL`
- Verify the chart exists: `helm repo add <name> <url> && helm search repo <chart> --versions`

### 5. CRD missing (resource kind not recognized)

**Error:** `no matches for kind "X" in version "Y"` during sync

**Check:**
```bash
kubectl get crd <kind-plural>.<api-group> 2>&1
```

**Fix:** The controller that owns this CRD is not installed or was removed.
- Check the ArgoCD Application that manages the controller
- If it's a Crossplane CRD, check provider health: `kubectl get providers.pkg.crossplane.io`

### 6. Application stuck in Terminating state

**Check:**
```bash
argocd app get <app-name> -o json | jq '{
  deletionTimestamp: .metadata.deletionTimestamp,
  finalizers: .metadata.finalizers
}'

# Find what's blocking deletion
argocd app get <app-name> -o json | jq '.status.resources[] |
  select(.status == "SyncFailed" or .health.status == "Unknown") |
  "\(.kind)/\(.name)"'
```

**Temporary unblock:**
```bash
# Option 1: Fix the blocking resources, then the app deletes naturally

# Option 2: Remove the ArgoCD finalizer (WARNING: orphans managed resources)
kubectl -n argocd patch application <app-name> \
  --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

**Permanent fix:** Resolve the underlying resource issue (stuck Crossplane claim,
missing CRD, etc.) so cascade deletion can complete normally.

### 7. Sync hangs indefinitely

**Check:**
```bash
# Application controller logs
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-application-controller \
  --tail=100 | grep -i "<app-name>"
```

**Temporary unblock:**
```bash
# Force terminate the current sync operation
argocd app terminate-op <app-name>

# Then retry
argocd app sync <app-name>
```

## Force Sync Options

When a standard sync doesn't resolve the issue:

```bash
# Standard resync
argocd app sync <app-name>

# Force sync (replaces changed resources)
argocd app sync <app-name> --force

# Sync with prune (removes resources not in git)
argocd app sync <app-name> --prune

# Hard refresh (clear ArgoCD's cache of the repo)
argocd app get <app-name> --hard-refresh
```

## Post-Resolution

1. Verify the app converges: `argocd app wait <app-name> --health --timeout 120`
2. Check all resources are healthy: `argocd app get <app-name>`
3. If the fix was an IaC change, run `/mobius:validate-service` to confirm overall health
