# Workflow: Debugging ApplicationSet Discovery Failures

> **Claude + Codex compatible**: This workflow is written for both human
> engineers and AI agents. Follow steps in order — each step narrows the
> cause before the next. Do not skip steps.

---

## Purpose

Diagnoses and fixes cases where an ArgoCD ApplicationSet fails to discover
addon overlays (config.yaml files) and create the expected Applications.

**When to use this workflow**:
- You added a config.yaml to `iac-eks-addons` but no Application appeared in ArgoCD
- An Application existed but disappeared after a branch change
- An ApplicationSet shows errors or generates wrong Applications
- A newly merged addon hasn't deployed after 10+ minutes

---

## Inputs Required

| Input | Example | How to find |
|-------|---------|-------------|
| Addon name | `cert-manager` | Directory name in `iac-eks-addons/argocd/` |
| Environment | `bg-qa` | Overlay directory name |
| ApplicationSet name | `core-addons` | `kubectl get applicationset -n argocd` |
| Expected Application name | `bg-qa-cert-manager` | `{cluster}-{addon}` convention |

---

## Repositories / Files Involved

| Repo | Files | Role |
|------|-------|------|
| `iac-eks-addons` | `argocd/<addon>/overlays/<env>/config.yaml` | Discovery trigger |
| `iac-eks-argocd` | `applicationsets/.../<appset>.yaml` | Generator configuration |
| `iac-eks-argocd` | `projects/<project>.yaml` | Permission gating |

> **Skill reference**: `iac-eks-argocd/.claude/skills/argocd-applicationset-wiring/SKILL.md`
> has a focused debugging checklist for discovery issues.

---

## Diagnostic Flow (Follow in Order)

```
Application missing in ArgoCD?
    │
    ├─► Step 1: config.yaml exists?
    │       NO  → Create it (see add-service.md)
    │       YES → Step 2
    │
    ├─► Step 2: config.yaml content valid?
    │       NO  → Fix fields
    │       YES → Step 3
    │
    ├─► Step 3: config.yaml on main branch?
    │       NO  → Merge to main first
    │       YES → Step 4
    │
    ├─► Step 4: ApplicationSet generator path matches overlay path?
    │       NO  → Fix path pattern
    │       YES → Step 5
    │
    ├─► Step 5: ApplicationSet has errors?
    │       YES → Fix (see Step 5 below)
    │       NO  → Step 6
    │
    └─► Step 6: ArgoCD project permits source + destination?
            NO  → Update project
            YES → Step 7: controller logs
```

---

## Step-by-Step Procedure

### Step 1 — Verify config.yaml exists

```bash
# Check config.yaml is present in the overlay
ls argocd/<addon>/overlays/<env>/config.yaml
```

If missing: follow [add-service.md](../services/add-service.md) to create it.

Check count matches number of overlays:
```bash
find argocd/<addon>/overlays -name "config.yaml" | sort
```

---

### Step 2 — Validate config.yaml content

```bash
cat argocd/<addon>/overlays/<env>/config.yaml
```

Required fields:
```yaml
repoURL: "https://github.com/boatsgroup/iac-eks-addons"
targetRevision: "main"
cluster: "<env>"        # Exact cluster name — must match what Application expects
```

**Common mistakes**:

| Mistake | Effect |
|---------|--------|
| `cluster: bg_qa` (underscore) | Application name wrong — may not match expected name |
| `targetRevision: HEAD` | May work, but not the standard — use `"main"` |
| `testBranch: feature/xyz` | ONLY works when config.yaml is on `main`; on feature branch, ignored |
| Extra unknown fields | May cause `missingkey=error` in ApplicationSet template |

---

### Step 3 — Confirm config.yaml is merged to main

```bash
git log --oneline origin/main -- argocd/<addon>/overlays/<env>/config.yaml | head -3
```

If config.yaml is not on main, the Git File Generator won't see it.
`testBranch` is a field inside config.yaml that redirects the Application's
`targetRevision` — it does NOT affect which branch the generator scans.

```bash
# Verify generator scans main
kubectl get applicationset -n argocd <appset-name> -o jsonpath='{.spec.generators[0].git.revision}'
# Should be: main
```

---

### Step 4 — Verify generator path pattern

The ApplicationSet's Git File Generator uses a glob path. Check it matches
your config.yaml location:

```bash
kubectl get applicationset -n argocd <appset-name> -o yaml | grep -A5 "files:"
```

Expected output (standard pattern):
```yaml
files:
  - path: "argocd/*/overlays/*/config.yaml"
```

Check your config.yaml location:
```bash
# Path relative to repo root (must match the glob)
realpath --relative-to=. argocd/<addon>/overlays/<env>/config.yaml
# Should output: argocd/<addon>/overlays/<env>/config.yaml
# ✓ Matches pattern: argocd/*/overlays/*/config.yaml
```

If your overlay is nested deeper (e.g., `argocd/<addon>/overlays/<env>/sub/config.yaml`),
the pattern won't match — restructure to match the standard layout.

---

### Step 5 — Check ApplicationSet status and events

```bash
# Overall status
kubectl describe applicationset -n argocd <appset-name>

# Status conditions
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.status.conditions}' | jq .

# Recent events
kubectl get events -n argocd \
  --field-selector involvedObject.name=<appset-name> \
  --sort-by='.lastTimestamp'
```

**Common ApplicationSet errors**:

| Error | Cause | Fix |
|-------|-------|-----|
| `error evaluating git files` | Git repo not accessible | Check ArgoCD can reach GitHub; verify repoURL |
| `failed to get repo` | Repository credential missing | Add repo to ArgoCD credentials |
| `missing key in params` | config.yaml missing field used in template | Add field to config.yaml |
| `template error` | Invalid Go template in ApplicationSet | Fix template syntax |

---

### Step 6 — Check ArgoCD project permissions

The Application is generated with a `project:` reference. If the project
doesn't permit the source or destination, the Application will be created
but immediately fail sync.

```bash
# Get the project name from the ApplicationSet template
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.spec.template.spec.project}'

# Inspect the project
kubectl get appproject -n argocd <project-name> -o yaml
```

Check:
1. `sourceRepos` contains the `repoURL` from config.yaml
2. `destinations` contains the `namespace` the addon deploys to

If either is missing: follow the project update steps in
[new-project-or-applicationset.md](new-project-or-applicationset.md).

---

### Step 7 — Check ApplicationSet controller logs

Last resort — check the controller for errors not surfaced in status:

```bash
# ApplicationSet controller logs (last 200 lines)
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-applicationset-controller \
  --tail=200 | grep -E "(error|Error|<addon>|<appset-name>)"

# Application controller logs
kubectl logs -n argocd \
  -l app.kubernetes.io/name=argocd-application-controller \
  --tail=100 | grep -E "(error|Error|<addon>)"
```

---

### Step 8 — Force ApplicationSet refresh

If all config is correct but the Application still hasn't appeared:

```bash
# Trigger ApplicationSet reconciliation
kubectl annotate applicationset -n argocd <appset-name> \
  argocd.argoproj.io/refresh=normal --overwrite

# Wait 30 seconds, then check
sleep 30
kubectl get applications -n argocd | grep <addon>
```

Or via ArgoCD CLI (requires auth — see `argocd-cli-auth` skill):
```bash
argocd appset get <appset-name>
```

---

## Validation Commands

```bash
# 1. config.yaml present and correct
cat argocd/<addon>/overlays/<env>/config.yaml

# 2. config.yaml on main
git log --oneline origin/main -- argocd/<addon>/overlays/<env>/config.yaml | head -1

# 3. ApplicationSet healthy
kubectl get applicationset -n argocd <appset-name> \
  -o jsonpath='{.status.conditions[?(@.type=="ErrorOccurred")].status}'
# Expected: False

# 4. Application generated
kubectl get applications -n argocd | grep <addon>

# 5. Application synced
kubectl get applications -n argocd <cluster>-<addon> \
  -o jsonpath='{.status.sync.status}'
# Expected: Synced

# 6. Addon pods running
kubectl -n <namespace> get pods
```

---

## Failure Modes (Summary)

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| No Application generated | config.yaml missing or wrong path | Create config.yaml; check path matches generator pattern |
| No Application generated | config.yaml on feature branch | Merge to main |
| Application created, sync fails | Project missing sourceRepo | Add to project `sourceRepos` |
| Application created, sync fails | Project missing destination namespace | Add to project `destinations` |
| Application created, immediately deleted | ApplicationSet generator no longer sees config.yaml | Check config.yaml wasn't removed |
| Wrong targetRevision used | `testBranch` on feature branch | `testBranch` only works when config.yaml is on main |
| ApplicationSet shows `ErrorOccurred` | Template error or missing repo | Check ApplicationSet events and controller logs |

---

## Quick Reference — Most Common Issue

**"I added config.yaml but no Application appeared."**

Run this sequence:
```bash
# 1. Is it on main?
git log --oneline origin/main -- argocd/<addon>/overlays/<env>/config.yaml

# 2. Is the path correct?
find argocd/<addon>/overlays -name "config.yaml"

# 3. Does the ApplicationSet have errors?
kubectl describe applicationset -n argocd <appset-name> | grep -A5 "Status:"

# 4. Force refresh
kubectl annotate applicationset -n argocd <appset-name> \
  argocd.argoproj.io/refresh=normal --overwrite
```
