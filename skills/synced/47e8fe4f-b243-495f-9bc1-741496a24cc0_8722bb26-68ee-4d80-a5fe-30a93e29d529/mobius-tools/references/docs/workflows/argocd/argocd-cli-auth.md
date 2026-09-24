# ArgoCD CLI Authentication

> **Prerequisite for all ArgoCD CLI operations.** Always authenticate before
> running `argocd` commands. This applies to both human engineers and AI agents
> (Claude Code, Codex CLI).

---

## Credentials

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | Retrieved from Kubernetes secret (see below) |

---

## Hub Resolution

Each environment is managed by a specific hub cluster. **Do not guess based on
name similarity** — `bg-qa` is managed by `ops-prod`, not `ops-qa`.

| Environment | Hub Cluster | kubectl context | ArgoCD URL |
|-------------|-------------|-----------------|------------|
| `ops-qa` | ops-qa | ops-qa | `argo.qa.ops.bgrp.io` |
| `bg-dev` | ops-qa | ops-qa | `argo.qa.ops.bgrp.io` |
| `ops-prod` | ops-prod | ops-prod | `argo.prod.ops.bgrp.io` |
| `bg-qa` | ops-prod | ops-prod | `argo.prod.ops.bgrp.io` |
| `bg-prod` | ops-prod | ops-prod | `argo.prod.ops.bgrp.io` |

When in doubt, discover the mapping from the repo itself:

```bash
# List which hub manages which environments
ls iac-eks-argocd/hubs/*/environments/
```

The directory structure `hubs/<hub>/environments/<env>/` is the live source of
truth — it updates automatically as spokes are registered via `/mobius:new-spoke`.

---

## Full Authentication Flow

### Step 1: Verify kubectl context

Ensure you are connected to the correct hub cluster before retrieving secrets:

```bash
kubectl config current-context
# Should show the hub cluster (ops-qa or ops-prod)

# If not connected, set context via AWS SSO:
aws sso login --profile <profile>
aws eks update-kubeconfig --name <cluster-name> --region us-east-1 --profile <profile>
```

### Step 2: Get the ArgoCD admin password

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)
```

### Step 3: Login to ArgoCD

```bash
# For ops-qa hub
argocd login argo.qa.ops.bgrp.io --username admin --password "$ARGOCD_PASSWORD"

# For ops-prod hub
argocd login argo.prod.ops.bgrp.io --username admin --password "$ARGOCD_PASSWORD"
```

### Step 4: Verify login

```bash
argocd app list
# Should return the list of managed applications
```

---

## One-Liners (Quick Reference)

```bash
# ops-qa — login in one command
argocd login argo.qa.ops.bgrp.io --username admin --password \
  $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

# ops-prod — login in one command
argocd login argo.prod.ops.bgrp.io --username admin --password \
  $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)
```

---

## Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| `error: secrets "argocd-initial-admin-secret" not found` | Wrong namespace or secret deleted | Run `kubectl get secret -n argocd` to list available secrets |
| `FATA[0000] rpc error: transport: connection refused` | Not on VPN or DNS not resolving | Verify network access: `nslookup argo.qa.ops.bgrp.io` |
| `FATA[0000] rpc error: invalid credentials` | Password was rotated | Re-retrieve from secret; check if `argocd-initial-admin-secret` still exists |
| `Unable to connect to the server` | kubectl not pointed at hub cluster | Run `kubectl config current-context` and switch if needed |
| `argocd: command not found` | CLI not installed | Install: `brew install argocd` |

---

## AWS SSO Profile Selection

Before kubectl can access the hub cluster, you need an active AWS SSO session:

```bash
# List available profiles
aws configure list-profiles

# Login to the correct profile
aws sso login --profile <profile>

# Update kubeconfig for the hub cluster
aws eks update-kubeconfig --name <cluster-name> --region us-east-1 --profile <profile>
```

Common profiles:
- QA hub cluster: typically uses a QA/dev AWS profile
- Prod hub cluster: typically uses a prod AWS profile

The exact profile names are org-specific. Ask your team if unsure.

---

## For AI Agents (Claude Code / Codex CLI)

When an agent needs to run `argocd` commands:

1. Check if `argocd` CLI is available: `which argocd`
2. If not installed, ask the user: "ArgoCD CLI is not installed. Can I install it with `brew install argocd`?"
3. Check if already logged in: `argocd app list 2>&1` — if it succeeds, skip auth
4. If not logged in, follow the full authentication flow above
5. Ask the user which hub to target (ops-qa or ops-prod) if not obvious from context

**Never hardcode passwords.** Always retrieve from the Kubernetes secret at runtime.

---

## Referenced By

| Command | Why |
|---------|-----|
| `/mobius:debug-service` | Authenticates before runtime debugging |
| `/mobius:debug-appset` | Authenticates before ApplicationSet diagnostics |
