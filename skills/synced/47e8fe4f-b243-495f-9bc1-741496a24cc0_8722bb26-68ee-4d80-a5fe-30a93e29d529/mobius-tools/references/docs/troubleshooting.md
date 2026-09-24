# Mobius Tools — Troubleshooting Guide

> Quick diagnostics: `npx mobius-validate-graph`
> For setup issues, start with: `node --version && npm --version && gh auth status`

---

## Table of Contents

1. [Resolver Issues](#1-resolver-issues)
2. [Authentication Issues](#2-authentication-issues)
3. [Repository Issues](#3-repository-issues)
4. [Claude Code Settings Issues](#4-claude-code-settings-issues)
5. [Drift Detection Issues](#5-drift-detection-issues)
6. [XRD / Crossplane Issues](#6-xrd--crossplane-issues)
7. [Kustomize / ArgoCD Issues](#7-kustomize--argocd-issues)
8. [Environment Generation Issues](#8-environment-generation-issues)

---

## 1. Resolver Issues

### "command not found: gh"

**Symptom**: Running the resolver fails immediately with `gh: command not found`.

**Cause**: GitHub CLI is not installed.

**Fix**:
```bash
brew install gh
gh auth login
```

---

### "command not found: jq"

**Symptom**: Resolver runs but fails when trying to update settings.local.json.

**Cause**: `jq` is not installed.

**Fix**:
```bash
brew install jq
```
---

### "command not found: node" or "command not found: npx"

**Symptom**: Running `npx mobius-validate-*` fails with `node: command not found` or `npx: command not found`.

**Cause**: Node.js is not installed. Required for TypeScript CLI validators (≥ 18).

**Fix**:
```bash
brew install node
node --version   # should be v18+
npm --version
```

If you have Node.js but it's too old:
```bash
brew upgrade node
```


---

### "No frontmatter found in AGENTS.md"

**Symptom**: Resolver exits with `No mobius frontmatter found` or similar.

**Cause**: The repo's AGENTS.md does not have the YAML frontmatter block at the top.

**Fix**: Add the frontmatter block to the top of AGENTS.md:
```yaml
---
mobius:
  repo: {your-repo-name}
  org: boatsgroup
  dependencies:
    - {dep-1}
    - {dep-2}
---
```

Use `mobius-tools/templates/agents-frontmatter.md` as the template.

---

### "No cross-repo dependencies declared"

**Symptom**: Resolver exits cleanly with "No cross-repo dependencies" message.

**Cause**: The frontmatter has `dependencies: []` — this is correct behavior for
repos with no cross-repo deps (like `helm-charts` and `mobius-tools`).

**Not a bug**: This is expected. No action needed.

---

### "Already resolved today, skipping"

**Symptom**: Resolver skips and exits immediately.

**Cause**: Session deduplication — the resolver already ran for this repo today
in this user context (session marker at `/tmp/mobius-resolved-{uid}-{date}`).

**Fix** (if you need to force re-run):
```bash
rm /tmp/mobius-resolved-$(id -u)-$(date +%Y%m%d) 2>/dev/null
bash ../mobius-tools/scripts/resolve-deps.sh
```

---

### Resolver cloned wrong repo

**Symptom**: The resolver cloned a repo but it's the wrong one (unrelated project
with the same name).

**Cause**: `discover-repo.sh` validates the git remote before accepting a found
repo. If you see a wrong repo, the validation may have failed silently.

**Fix**:
```bash
# Check the remote of the cloned repo
cd ../suspected-wrong-repo && git remote -v

# If wrong, remove and re-clone
cd .. && rm -rf suspected-wrong-repo
gh repo clone boatsgroup/correct-repo-name
```

---

## 2. Authentication Issues

### "gh: not authenticated"

**Symptom**: `gh repo clone` fails with authentication error.

**Fix**:
```bash
gh auth login
# Choose: GitHub.com -> HTTPS -> Yes to git auth
```

Verify: `gh auth status` should show `Logged in to github.com as {username}`

---

### "gh: Permission denied to boatsgroup/..."

**Symptom**: Clone succeeds for public repos but fails for private repos.

**Cause**: Your GitHub account doesn't have access to the `boatsgroup` org.

**Fix**: Contact the platform team to add your account to the `boatsgroup` org.

---

### Clone succeeds but push fails

**Symptom**: You can clone repos but `git push` fails.

**Cause**: The HTTPS credential helper may not be wired to `gh auth`.

**Fix**:
```bash
gh auth setup-git
```

This configures git to use `gh` as the credential helper for GitHub.

---

## 3. Repository Issues

### Dependency repo exists but resolver skips freshening

**Symptom**: `Warning: {dep-name} has uncommitted changes — skipping pull`

**Cause**: The dependency repo has uncommitted changes (dirty working tree).

**Fix** (choose one):
```bash
# Option A: Stash changes
cd ../dep-name && git stash

# Option B: Commit changes if they're intentional
cd ../dep-name && git add . && git commit -m "wip: save changes"

# Option C: Discard changes (CAREFUL)
cd ../dep-name && git checkout -- .
```

Then re-run the resolver.

---

### Resolver warns "on branch {X} — skipping pull"

**Symptom**: `Warning: {dep-name} on branch feature/xyz — skipping pull`

**Cause**: The dependency repo is on a feature branch. The resolver only freshens
repos on `main` to avoid clobbering your work-in-progress.

**This is correct behavior**. The resolver is protecting your work.

If you want to update to latest main:
```bash
cd ../dep-name && git checkout main && git pull origin main
```

---

### "fatal: repository 'boatsgroup/{repo}' not found"

**Symptom**: Clone fails with "repository not found".

**Cause**: Either the repo name is wrong (typo in AGENTS.md frontmatter) or you
don't have access.

**Fix**:
1. Check the frontmatter: `grep "dependencies" AGENTS.md`
2. Check the repo exists: `gh repo view boatsgroup/{repo-name}`
3. If repo name is wrong, fix the AGENTS.md frontmatter

---

### Resolver finds repo at unexpected path

**Symptom**: Resolver uses a different path than expected.

**Cause**: `discover-repo.sh` has two search paths:
1. `../{repo-name}/` (sibling — primary)
2. `$MOBIUS_WORKSPACE/{repo-name}/` (env var, if set)

If `$MOBIUS_WORKSPACE` is set in your shell, it may override the sibling path.

**Fix**:
```bash
echo $MOBIUS_WORKSPACE  # Check if set
unset MOBIUS_WORKSPACE  # Clear if causing issues
```

---

## 4. Claude Code Settings Issues

### additionalDirectories not updated

**Symptom**: Resolver reports success but Claude Code can't access dependency repos.

**Cause**: `settings.local.json` may not have been updated, or Claude Code needs
to restart to pick up changes.

**Fix**:
```bash
# Check the settings file
cat .claude/settings.local.json | jq '.permissions.additionalDirectories'

# If empty or missing, re-run resolver
bash ../mobius-tools/scripts/resolve-deps.sh

# Restart Claude Code session to pick up new settings
```

---

### settings.local.json has duplicate paths

**Symptom**: `additionalDirectories` contains the same path multiple times.

**Cause**: The resolver ran multiple times without deduplication working.

**Fix**: The resolver deduplicates on every run. Simply run it again:
```bash
bash ../mobius-tools/scripts/resolve-deps.sh
```

Or manually edit the file:
```bash
# Remove duplicates with jq
cat .claude/settings.local.json | jq '.permissions.additionalDirectories |= unique' > /tmp/settings.tmp
mv /tmp/settings.tmp .claude/settings.local.json
```

---

### settings.local.json is corrupted / invalid JSON

**Symptom**: Resolver fails with jq parse error.

**Fix**:
```bash
# Check what's in the file
cat .claude/settings.local.json

# If corrupted, reset it
echo '{"permissions": {"additionalDirectories": []}}' > .claude/settings.local.json

# Re-run resolver
bash ../mobius-tools/scripts/resolve-deps.sh
```

---

### Claude Code can't write to settings.local.json

**Symptom**: Permission denied when resolver tries to update settings.

**Fix**:
```bash
# Check permissions
ls -la .claude/settings.local.json

# Fix permissions
chmod 644 .claude/settings.local.json
```

---

## 5. Drift Detection Issues

### validate-graph.sh: "repo not found locally, skipping"

**Symptom**: The validate script says a repo isn't on disk.

**Cause**: That repo hasn't been cloned locally — expected if you're doing
partial platform setup.

**Not an error** unless you expected that repo to be present.

---

### validate-graph.sh: "DRIFT DETECTED: {repo}"

**Symptom**: The validate script reports a mismatch between AGENTS.md frontmatter
and dependency-graph.yaml.

**Cause**: Someone updated one source but not the other.

**Fix**:
1. Read both files: `cat ../{repo}/AGENTS.md | head -20` and
   `cat ecosystem/dependency-graph.yaml | grep -A5 "{repo}:"`
2. Determine which is correct (usually the per-repo frontmatter, since that
   was updated intentionally)
3. Update the other source to match
4. Re-run `validate-graph.sh`

---

### validate-graph.sh: cannot parse YAML

**Symptom**: Validate script errors on parsing dependency-graph.yaml.

**Cause**: The YAML may have invalid syntax.

**Fix**:
```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('ecosystem/dependency-graph.yaml'))" 2>&1

# Or with a dedicated linter
brew install yamllint
yamllint ecosystem/dependency-graph.yaml
```

---

## 6. XRD / Crossplane Issues

### "No Composition found for claim"

**Symptom**: A Crossplane claim is stuck in `Unresolvable` state with this error.

**Cause**: The XRD/Composition hasn't been registered yet. Crossplane's Configuration
CR (in iac-eks-crossplane) hasn't been synced by ArgoCD.

**Fix sequence**:
1. Check if the Configuration CR is deployed: `kubectl get configuration`
2. If not: check ArgoCD sync status for `iac-eks-crossplane`
3. If sync failed: check ArgoCD logs for the Configuration CR
4. If OCI package missing: verify the XRD repo was tagged and GitHub Actions ran

---

### "Configuration stuck in Installing state"

**Symptom**: `kubectl get configuration {name}` shows `INSTALLED: False`.

**Cause #1**: Missing `skipDependencyResolution: true` in crossplane.yaml.
Crossplane's own dependency resolution conflicts with ArgoCD-managed functions.

**Fix**: Add to the XRD repo's `crossplane.yaml`:
```yaml
spec:
  skipDependencyResolution: true
```

**Cause #2**: OCI package version doesn't exist in JFrog.

**Fix**:
```bash
# Check if the package exists
crane ls boatsgroup.pe.jfrog.io/bg-crossplane/{package-name}

# If missing, check GitHub Actions ran successfully after the git tag
```

---

### KCL composition fails to render

**Symptom**: Crossplane claim is stuck, events show KCL function error.

**Debug locally**:
```bash
cd crossplane-xrd-{name}/kcl
kcl run . -S items -D "params=$(cat ../test/basic.json)"

# Or with make
make test
make render
```

---

### KCL explicit import error

**Symptom**: `KCL error: module 'helpers' not found` or similar import error.

**Cause**: Explicit imports in `main.k` (`import helpers`). KCL flat-file pattern
means all `.k` files in the same directory share a namespace — imports are wrong.

**Fix**: Remove all `import` statements from `kcl/main.k`. Reference helpers
and config variables directly.

---

## 7. Kustomize / ArgoCD Issues

### "kustomize build fails"

**Symptom**: `kustomize build argocd/{addon}/overlays/{env}` fails.

**Common causes**:

```bash
# Missing base reference
grep "bases:" kustomize.yaml  # Check for dangling references

# Missing resource file
kustomize build 2>&1 | grep "no such file"

# Invalid patch format
kustomize build 2>&1 | grep "error: invalid"
```

---

### ApplicationSet doesn't discover config.yaml

**Symptom**: Added a config.yaml but ArgoCD didn't create a new Application.

**Check sequence**:
```bash
# 1. Verify path matches ApplicationSet pattern
# Pattern: argocd/{addon}/overlays/*/config.yaml
ls argocd/{addon}/overlays/{env}/config.yaml

# 2. Verify config.yaml content is valid
cat argocd/{addon}/overlays/{env}/config.yaml

# 3. Check ArgoCD ApplicationSet status
kubectl -n argocd get appset {appset-name} -o yaml | grep -A10 "status"

# 4. Refresh ApplicationSet
argocd appset get {appset-name}
```

**Gotcha**: `testBranch` in config.yaml only takes effect on the **main** branch.
If you're testing from a feature branch, the Application won't be created.

---

### ArgoCD sync fails with "Helm chart not found"

**Symptom**: Application created but sync fails looking for chart.

**Cause**: helm-charts repo may not have the chart at the referenced version.

**Fix**:
```bash
# Check the chart exists in helm-charts
ls ../helm-charts/charts/{chart-name}/

# Check the version in Chart.yaml matches what's referenced
cat ../helm-charts/charts/{chart-name}/Chart.yaml | grep version
```

---

## 8. Environment Generation Issues

### argocd-env-generator discovers zero services

**Symptom**: Running `argocd-env-generator discover` shows no repos or services.

**Cause sequence**:
1. ApplicationSets directory path wrong in config
2. Primary repo not found at expected path
3. ApplicationSet YAML malformed
4. No `git` generators in ApplicationSets

**Debug**:
```bash
# Check ApplicationSets directory exists
ls ../iac-eks-argocd/applicationsets/core-infrastructure/

# Run discover with verbose output
./bin/spoke-generator discover -c config.yaml
```

---

### Generated output contains unreplaced values

**Symptom**: Files in `outputs/` still contain the reference environment name.

**Cause**: Replacement string not covering all variants (e.g., `bg-qa` but not
all-caps `BG-QA` in resource names).

**Fix**:
```bash
# Find all unreplaced occurrences
grep -r "bg-qa" outputs/

# Add missing variants to config replacements
```

---

### Replacement corrupted a YAML key

**Symptom**: Generated kustomization.yaml is invalid.

**Cause**: A replacement string matched a YAML structure key, not just a value.

**Example**: Replacing `qa` in a file where `qa` appears in a key name like
`bg-qa-cluster-secret` that's used as a YAML key.

**Fix**: Use only fully-qualified, non-overlapping replacement strings.
Use `bg-qa` instead of `qa`. Never use bare environment name fragments.

---

## Quick Diagnostic Checklist

Run these in order when something's wrong:

```bash
# 1. Auth OK?
gh auth status

# 2. jq installed?
jq --version

# 3. Frontmatter present?
head -15 AGENTS.md

# 4. mobius-tools available?
ls ../mobius-tools/scripts/resolve-deps.sh

# 5. Run resolver
bash ../mobius-tools/scripts/resolve-deps.sh

# 6. Check settings updated
cat .claude/settings.local.json | jq '.permissions.additionalDirectories'

# 7. Check graph drift
npx mobius-validate-graph

# 8. Platform-level: all repos present?
ls /path/to/your/mobius-workspace/ | wc -l  # Compare against ecosystem/dependency-graph.yaml repo count
```
