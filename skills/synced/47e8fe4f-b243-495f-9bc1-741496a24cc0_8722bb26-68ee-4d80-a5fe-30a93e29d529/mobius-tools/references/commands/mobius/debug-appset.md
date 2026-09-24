---
name: debug-appset
description: Diagnose ApplicationSet discovery failures
argument-hint: <applicationset-name>
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->


# Debug ApplicationSet Discovery

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-8` or OpenAI `o3`).
>
> This diagnostic requires reasoning across multiple repository boundaries to
> trace config.yaml discovery failures through ApplicationSet generators, project
> permissions, and kustomization hierarchies. Weaker models may miss cross-repo
> wiring issues or suggest fixes in the wrong repository.

This command provides a structured diagnostic flow for ApplicationSet issues.
**Follow the layers in order** - do not skip steps.

---

## Canonical Rules

- **This command is READ-ONLY during diagnosis.** Run `kubectl`, `argocd`, and `git log/show/diff` commands only. Do NOT write files, stage changes, commit, or push during any diagnostic layer.
- **No direct commits to `main` or any branch.** If a fix is identified, present it to the user as a proposed change — do not apply it.
- **Fix workflow is required for any change.** If the user approves a fix:
  1. Prompt for JIRA ticket (reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt).
  2. Create a feature branch: `feat/<jira_ticket_id>-fix-<appset-name>` (or `feat/fix-<appset-name>` if no ticket).
  3. Apply the fix on the branch.
  4. Create a PR — never commit directly to `main`.
- **Route structural fixes to the right command.** Missing config.yaml → `/mobius:add-service`. Missing ApplicationSet wiring → `/mobius:add-service`. These commands enforce their own branch gates.

---

## Architecture Context

> When you need platform reasoning beyond this spec, read:
> - [ArgoCD Hub-Spoke](../../docs/architecture/argocd-hub-spoke.md) — ApplicationSet generators, project RBAC, kustomization hierarchy

---

## Prerequisites

> **Module**: Read [`shared/workspace-resolution.md`](shared/workspace-resolution.md) and resolve `workspace_dir` first. Every `../<repo>` below is `<workspace_dir>/<repo>`.

Before running diagnostics, ensure ArgoCD CLI access:

1. **kubectl** pointed at the correct hub cluster (see Hub Resolution below)
2. **ArgoCD CLI** authenticated — see `docs/workflows/argocd/argocd-cli-auth.md`

Layers 4–8 below require live cluster access via `kubectl` and/or `argocd` CLI.

### Hub Resolution

> See the full environment→hub mapping in
> [`docs/workflows/argocd/argocd-cli-auth.md`](../../docs/workflows/argocd/argocd-cli-auth.md#hub-resolution).

**Key rule:** `bg-qa` and `bg-prod` are managed by **`ops-prod`**, not `ops-qa`.
When in doubt, check `iac-eks-argocd/hubs/*/environments/` to discover the mapping.

Before Layer 4, switch to the correct hub context:

```bash
kubectl config use-context <hub-context>
```

---

## Workflow Reference

Follow the canonical workflow at:
**`../mobius-tools/docs/workflows/argocd/debug-applicationset.md`**

---

## Layer-by-Layer Diagnostics

Run through these layers sequentially. Each layer must pass before checking
the next.

### Layer 1: config.yaml Existence

```bash
# Check config.yaml exists in the overlay
ls argocd/<addon>/overlays/<env>/config.yaml

# Count config.yaml files (should match overlay count)
rg --files argocd/<addon>/overlays/ | rg "config.yaml" | wc -l
```

**If missing:** Create config.yaml using `/mobius:add-service`

---

### Layer 2: config.yaml Content

```bash
cat argocd/<addon>/overlays/<env>/config.yaml
```

**Required fields:**
- `addon`, `environment`, `enabled`
- `git.repoURL`, `git.overlayPath`
- `helm.repoURL`, `helm.chart`, `helm.version`
- `argocd.project`

**Common mistakes:**
- Underscore in cluster name (`bg_qa` vs `bg-qa`)
- Wrong `testBranch` usage (only works when config.yaml is on main)

---

### Layer 3: config.yaml on Main Branch

```bash
# Check if config.yaml is committed to main
git log --oneline origin/main -- argocd/<addon>/overlays/<env>/config.yaml | head -3
```

**If not on main:** Generator won't see it. Merge to main first.

---

### Layer 4: Generator Path Pattern

```bash
# Get the ApplicationSet's generator path
kubectl get applicationset -n argocd <appset-name> -o yaml | grep -A5 "files:"
```

**Verify your config.yaml path matches the glob pattern:**
- Standard: `argocd/*/overlays/*/config.yaml`
- Your file: `argocd/<addon>/overlays/<env>/config.yaml`

Also verify `repoURL` in generator matches where your config.yaml lives.

---

### Layer 5: ApplicationSet Status

```bash
# Check ApplicationSet status and conditions
kubectl describe applicationset -n argocd <appset-name>

# Check for error conditions
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.status.conditions}' | jq .

# Recent events
kubectl get events -n argocd \
  --field-selector involvedObject.name=<appset-name> \
  --sort-by='.lastTimestamp'
```

**Common errors:**
- `error evaluating git files` - repo not accessible
- `missing key in params` - config.yaml missing required field
- `template error` - invalid Go template syntax
- Applications exist but parent bootstrap app never syncs → check `applicationsSync` field

**`applicationsSync` valid values** (invalid value silently blocks parent sync):

```bash
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.spec.applicationsSync}'
```

Valid: `create-only`, `create-update`, `create-delete`, `sync`. Any other value (e.g. `create-update-delete`) causes the ApplicationSet controller to error and skip generation.

---

### Layer 6: ArgoCD Project Permissions

```bash
# Get project name from ApplicationSet
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.spec.template.spec.project}'

# Check project permissions
kubectl get appproject -n argocd <project-name> -o yaml
```

**Verify:**
- `sourceRepos` contains your Git repo URL and Helm repo URL
- `destinations` contains the target namespace

---

### Layer 7: Controller Logs

> **Note:** All `argocd` CLI commands in this env require `--grpc-web`. Add the flag if you get `transport: Error while dialing` or `code = Unimplemented`.

```bash
# ApplicationSet controller logs
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-applicationset-controller \
  --tail=200 | rg -e "error|Error|<addon>"

# Application controller logs
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-application-controller \
  --tail=100 | rg -e "error|Error|<addon>"
```

---

### Layer 8: Force Refresh

If all config is correct but Application hasn't appeared:

```bash
# Trigger reconciliation via annotation
kubectl annotate applicationset -n argocd <appset-name> \
  argocd.argoproj.io/refresh=normal --overwrite

# Wait and check
sleep 30
kubectl get applications -n argocd | rg <addon>
```

**If annotation-based refresh doesn't work** (Application still at stale revision), the ArgoCD
Redis manifest cache may be stuck. Check repo-server logs for the signal:

```bash
# Look for "manifest cache hit" with a revision that doesn't match HEAD
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-repo-server \
  --tail=200 | rg "manifest cache"
# If you see hits for a sha that isn't current HEAD → cache is stale
```

Clear the manifest cache by restarting Redis (restarts repo-server too since it depends on it):

```bash
kubectl rollout restart deployment argocd-redis -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-redis -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
```

Then hard-refresh via CLI (more reliable than the annotation):

```bash
argocd app get <app-name> --hard-refresh --grpc-web
```

---

### Layer 9: Missing kustomization.yaml in Projects Directory

**Silent failure mode:** An ArgoCD project YAML can exist in
`iac-eks-argocd/projects/<group>/<subdir>/` but never get applied if the
subdirectory is missing from the parent `kustomization.yaml`. The ApplicationSet
will generate Applications that reference the project — then fail with
"project not permitted" or "namespace not permitted" because the project doesn't
actually exist on the cluster.

```bash
# 1. Verify the project exists on the cluster
kubectl get appproject -n argocd <project-name>
# If "NotFound" → the project YAML was never applied despite existing in git

# 2. Find the project YAML in iac-eks-argocd
rg -l "<project-name>" <workspace_dir>/iac-eks-argocd/projects/ --include="*.yaml"

# 3. Check if the directory containing that YAML is in the parent kustomization.yaml
PROJECT_DIR=$(dirname <path-to-project-yaml>)
cat ${PROJECT_DIR}/../kustomization.yaml | rg "${PROJECT_DIR##*/}"
# If no match → the subdirectory is missing from kustomization.yaml
```

**Fix:** Add the subdirectory to `iac-eks-argocd/projects/<group>/kustomization.yaml`:

```yaml
resources:
  - <subdir>/  # add this line
```

---

## Quick Diagnostic Script

Run this sequence for the most common issue ("config.yaml added but no Application"):

```bash
ADDON=<addon>
ENV=<env>
APPSET=<appset-name>

echo "=== Layer 1: config.yaml exists? ==="
ls argocd/$ADDON/overlays/$ENV/config.yaml

echo "=== Layer 3: On main? ==="
git log --oneline origin/main -- argocd/$ADDON/overlays/$ENV/config.yaml | head -1

echo "=== Layer 5: ApplicationSet status ==="
kubectl describe applicationset -n argocd $APPSET | grep -A5 "Status:"

echo "=== Layer 8: Force refresh ==="
kubectl annotate applicationset -n argocd $APPSET \
  argocd.argoproj.io/refresh=normal --overwrite
```

---

## Diagnostic Output Required

When reporting results, include output from:
1. `ls argocd/<addon>/overlays/<env>/config.yaml`
2. `git log --oneline origin/main -- <path>` 
3. `kubectl describe applicationset -n argocd <name>`
4. `kubectl get applications -n argocd | grep <addon>`

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:debug-service` | Diagnoses **runtime** failures after the Application is created; use when the app exists but pods/services are unhealthy |
| `/mobius:validate-service` | Validates service completeness **before merge**; catches structural issues that would prevent discovery |
| `/mobius:add-service` | Generates the service files that ApplicationSets discover |

---

## Why Summary

> **Module**: Read [`shared/why-summary.md`](shared/why-summary.md) and [`shared/repo-roles.md`](shared/repo-roles.md),
>   then generate the Why Summary using the context hints below.

**Command type**: diagnostic

**Context hints**:
- "Impact opener" → state what's not being discovered/deployed and why
- "What was accomplished" → describe the ApplicationSet diagnosis — why the deployment system can't find the service
- "Why it matters" → the service exists but isn't deploying because the system doesn't know about it
- "What happens next" → explain the fix to make the service discoverable

**Repo breakdown guidance**:
- iac-eks-argocd: where the discovery rules live — explain what's misconfigured
- Service repo: where the service config lives — explain if the config needs adjustment to match discovery rules
