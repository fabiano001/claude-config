# Engineer's Guide to Mobius

> This guide gets you deploying services, creating resources, and running
> diagnostics on the Mobius platform. No platform internals required —
> just commands and what to expect.

---

## First-Time Setup (5 minutes)

### 1. Install prerequisites

```bash
# macOS — install Homebrew first if needed: https://brew.sh
brew install gh jq node
```

Verify:
```bash
node --version   # should be v18+
npm --version
gh --version
git --version
```

### 2. Authenticate with GitHub

```bash
gh auth login
```

Choose GitHub.com, HTTPS, and authenticate git with GitHub credentials.
Verify: `gh auth status` should show your username.

### 3. Clone your working repo

```bash
# Example: if you're working in the addons repo
gh repo clone boatsgroup/iac-eks-addons
cd iac-eks-addons
```

### 4. Bootstrap the tools

```bash
[ -d "../mobius-tools" ] || gh repo clone boatsgroup/mobius-tools ../mobius-tools
bash ../mobius-tools/scripts/install-command-pack.sh --force
bash ../mobius-tools/scripts/resolve-deps.sh
```

This installs the `/mobius:*` commands and sets up cross-repo access.

### 5. See what's available

```
/mobius:help
```

You're ready.

---

## What Can I Do?

Every task below is handled by a single command. The command walks you through
questions, generates the right files, creates branches, and opens PRs for you.

### Deploy a new service to EKS

```
/mobius:add-service
```

**What it asks**: Service name, which repo, target environments, Helm chart details.
**What it does**: Creates all deployment files, wires up ArgoCD discovery, validates
everything, then commits and opens PRs for you.
**What you review**: Two PRs — one for ArgoCD wiring (merge first), one for your
service files (merge second). The command tells you the merge order.

### Change a service that's already deployed

```
/mobius:update-service
```

**What it asks**: Which service, and what to change — add an AWS resource / IAM
permission, bump the Helm chart version, or add a target environment.
**What it does**: Modifies the existing service's wiring in place (reusing the
same generators as add-service), validates it, and opens PRs.
**What you review**: The PRs for the changed wiring; for an AWS-resource add in
Terraform mode, a separate Terraform PR carrying the Atlantis plan.

### Create a new Crossplane resource

```
/mobius:new-xrd
```

**What it asks**: Resource name, API group, what AWS resources it provisions.
**What it does**: Creates a new repo with the resource definition, registers it
with the platform, and updates the ecosystem graph.

### Add an ArgoCD project or application discovery

```
/mobius:new-project
```

**What it asks**: Project name, which repos it should have access to, namespace targets.
**What it does**: Creates the project permissions and application discovery
configuration in the ArgoCD repo.

### Set up a new hub cluster

```
/mobius:new-hub
```

**What it asks**: Hub name, AWS account, region, DNS zone.
**What it does**: Bootstraps the full control plane across 3-5 repos — infrastructure,
ArgoCD, Crossplane, and optionally monitoring.

### Register a new spoke cluster

```
/mobius:new-spoke
```

**What it asks**: Hub name, spoke name, AWS account, region.
**What it does**: Registers the spoke with the hub and sets up addon deployments,
Crossplane config, and optionally monitoring across 4-6 repos.

### Migrate an ECS service to EKS

```
/mobius:migrate-ecs-service
```

**What it asks**: Service name, ECS cluster, AWS profile.
**What it does**: Discovers your ECS configuration, maps it to EKS equivalents,
generates the GitOps manifests, and validates parity with the original.

### Debug a running service

```
/mobius:debug-service api-node-payments --env bg-qa
```

**What it does**: Auto-diagnoses across ArgoCD, Kubernetes, and cloud resources.
Produces a structured report with what's wrong and how to fix it.

### Debug application discovery issues

```
/mobius:debug-appset core-infrastructure
```

**What it does**: Checks why ArgoCD isn't discovering or deploying your service.
Layer-by-layer diagnostics from repo paths to controller logs.

### Validate a service after changes

```
/mobius:validate-service api-node-payments --service-repo ../helm-charts
```

**What it does**: Checks build correctness, structural completeness, and
convention compliance. Reports pass/fail with specific issues to fix.

### Add observability instrumentation to a service

```
/mobius:instrument-service
```

**What it asks**: Discovery mode (guided questionnaire or AI-proposed SRE mode),
endpoint criticality preferences, and which telemetry signals to include.
**What it does**: Analyzes your Node.js codebase, classifies endpoints by criticality,
and generates production-ready OpenTelemetry instrumentation — SDK initialization,
custom spans for critical paths, metric views with cardinality controls,
structured logging, telemetry tests, Grafana dashboards, and runbooks.
**What you review**: One PR with instrumentation files. Run tests to verify
telemetry exports. See [ADR-004](decisions/004-standardized-otel-instrumentation.md)
for design rationale.

### Generate repo documentation (AGENTS.md and ecosystem context)

```
/mobius:document-repo
```

**What it asks**: Nothing up front — it analyzes your repo first, then shows you
what it found and what docs it proposes to generate. You review and approve.
**What it does**: Generates AGENTS.md with frontmatter and bootstrap instructions,
`docs/` folder with architecture, workflow, and dependency documentation,
`.claude/ecosystem.md` for AI agent context, and optionally registers the repo
in the Mobius ecosystem graph.
**What you review**: One PR with AGENTS.md and docs/ files. Check that the
architecture description and dependency mapping are accurate.

### Generate deep service documentation

```
/mobius:document-service
```

**What it asks**: In a monorepo, it lists all services pre-selected and asks if you want to deselect any (default is all). Then it analyzes the codebase and shows you what docs it proposes to generate. You review and approve.
**What it does**: Deep-dives your service code — maps every API endpoint, traces
request lifecycles, documents business logic, catalogs errors, and maps the
security model. Generates a service guide, API reference, developer guide, and
operations runbook.
**What you review**: One PR with up to 5 documentation files in `docs/`. Check that
the architecture description matches reality and the API reference is complete.

---

## What to Expect When Running a Command

Every command that creates or modifies files follows the same pattern:

1. **JIRA prompt** — You'll be asked if there's a Jira ticket for the work.
   You can skip this, but it's helpful for tracking.

2. **Questions** — The command asks you a series of questions about what you
   need. Answer them and confirm.

3. **Branch creation** — The command creates feature branches in all repos
   it needs to touch. If you already created a branch before running the
   command, it will ask if you want to use it.

4. **File generation** — Files are created across repos.

5. **Validation** — The command checks that everything is correct.

6. **Commit and PR** — Changes are committed and PRs are created automatically.
   You get PR URLs at the end with clear merge order instructions.

You don't need to manage git operations — the command handles branching,
committing, pushing, and PR creation.

---

## Common Questions

### "What's a service repo?"

The repository where your service's deployment configuration lives. For most
platform services, this is `iac-eks-addons`. For application teams, it's
typically your team's own repo. The command asks you which one during setup.

### "Why are there two PRs?"

Most changes touch two repos — the ArgoCD control plane repo (for permissions
and discovery) and your service repo (for the actual deployment files). They
need to be merged in order because ArgoCD needs permissions set up before it
can discover your service.

### "What's an overlay?"

A per-environment configuration folder. If you're deploying to `bg-qa` and
`bg-prod`, you'll have two overlays — one for each environment. Each overlay
customizes settings like resource sizes, replica counts, and feature flags
for that specific environment.

### "What happens after I merge the PRs?"

ArgoCD automatically detects the new configuration and creates your deployment.
No manual deployment step — merging the PR IS the deployment trigger.

### "I need to add an AWS IAM permission (or resource) to an existing service"

Use `/mobius:update-service` (add-resource mode):

```
/mobius:update-service <service-name>
```

It adds the IAM actions to the service's Crossplane `XIRSARole` claim (and, if
you're adding a whole resource like an S3 bucket, generates that too via the
service's existing crossplane/terraform path), validates the wiring, and opens
the PRs. This is the command that used to be missing — you no longer hand-edit
IaC for a service-level permission change.

> **Platform-level roles only** (the ArgoCD hub role, the External Secrets
> Operator role, the Crossplane provider role — roles that must exist before
> those controllers start) still live in `terraform-module-core-irsa`
> (`modules/{service}/iam.tf`) and are edited directly, since they're not
> service `XIRSARole` claims. `update-service` covers service-level IAM, not
> these bootstrap platform roles.

---

## Walkthrough: Deploy a Service from Scratch

This is a complete, end-to-end example of deploying `cert-manager` to EKS using
`/mobius:add-service`. Follow along to see exactly what happens at each step.

### Prerequisites

You've completed [First-Time Setup](#first-time-setup-5-minutes) above.
You're working from the `iac-eks-addons` repo.

### Step 1: Run the command

```
/mobius:add-service cert-manager
```

### Step 2: Answer the JIRA prompt

```
Before we begin, is there a Jira ticket for this service deployment?

1. Yes, I have a ticket → Enter ticket ID (e.g., PLAT-123)
2. No, create one for me
3. No ticket needed
```

Choose option 1 and enter `PLAT-456`. This ticket ID will appear in your
branch name, commit messages, and PR.

### Step 3: Answer intake questions

The command asks a series of questions. Here's what to expect and example answers:

```
Service repo?
  → iac-eks-addons (Recommended)               ← press enter for default

Helm chart source?
  → "cert-manager"                              ← just the chart name is enough

Target environments?
  → bg-qa,bg-prod (Recommended)                 ← press enter for default

AWS resources needed?
  → irsa-only                                   ← cert-manager needs IAM for DNS validation

ArgoCD project?
  → core-infrastructure (Recommended)           ← press enter for default
```

### Step 4: Review the Helm chart resolution

The command searches for the chart, validates it, and shows you what it found:

```
Found: cert-manager
  Repo:     https://charts.jetstack.io
  Chart:    cert-manager
  Versions: v1.14.4 (latest), v1.14.3, v1.14.2, v1.13.6
  
  Which version? v1.14.4 (Recommended — latest stable)
```

Press enter to accept the recommended version.

### Step 5: Review recommendations

The command presents its recommendations based on chart analysis and existing
patterns in the repo:

```
╔════════════════════════════════════════════════╗
║    RECOMMENDATIONS: cert-manager               ║
╚════════════════════════════════════════════════╝

  Namespace:     cert-manager
  Helm chart:    cert-manager v1.14.4 from https://charts.jetstack.io
  Environments:  bg-qa, bg-prod
  Project:       core-infrastructure
  IRSA:          Yes (XIRSARole for Route53 DNS validation)
  
  Overlay values (per-env):
    - installCRDs: true
    - replicas: 2 (prod), 1 (qa)
    - serviceAccount with IRSA annotation

  Does this look good? (yes / or tell me what to change)
```

Type `looks good` to proceed.

### Step 6: Branch creation (automatic)

The command creates feature branches in all affected repos:

```
Creating branches...
  ✓ iac-eks-addons:  feat/PLAT-456-add-cert-manager
  ✓ iac-eks-argocd:  feat/PLAT-456-add-cert-manager
```

If you were already on a feature branch, it asks whether to use it or create a new one.

### Step 7: File generation (automatic)

The command generates all required files:

```
Generating files...

  iac-eks-addons:
    ✓ argocd/cert-manager/base/kustomization.yaml
    ✓ argocd/cert-manager/base/xirsarole.yaml
    ✓ argocd/cert-manager/overlays/bg-qa/config.yaml
    ✓ argocd/cert-manager/overlays/bg-qa/kustomization.yaml
    ✓ argocd/cert-manager/overlays/bg-qa/values.yaml
    ✓ argocd/cert-manager/overlays/bg-prod/config.yaml
    ✓ argocd/cert-manager/overlays/bg-prod/kustomization.yaml
    ✓ argocd/cert-manager/overlays/bg-prod/values.yaml

  iac-eks-argocd:
    ✓ applicationsets/core-infrastructure/cert-manager.yaml (or updated existing)
    ✓ projects/devops/core-infrastructure/project.yaml (sourceRepos updated)
```

### Step 8: Validation (automatic)

The command runs the validator to check everything is wired correctly:

```
Running validation...
  npx mobius-validate-wiring add-service cert-manager \
    --service-repo ../iac-eks-addons --envs bg-qa,bg-prod

  ✓ config.yaml exists for bg-qa
  ✓ config.yaml exists for bg-prod
  ✓ config.yaml repoURL matches ApplicationSet generator
  ✓ ApplicationSet registered in kustomization.yaml
  ✓ ArgoCD project permits source repo
  ✓ Helm chart version pinned (not 'latest')

  RESULT: PASS
```

### Step 9: Commit and PR (automatic)

The command commits, pushes, and creates PRs:

```
Committing and pushing...

  iac-eks-argocd:
    ✓ Committed: feat(argocd): add cert-manager ApplicationSet and project wiring
    ✓ Pushed to origin/feat/PLAT-456-add-cert-manager
    ✓ PR created: https://github.com/boatsgroup/iac-eks-argocd/pull/42
      Title: "PLAT-456: Add cert-manager ApplicationSet and project wiring"

  iac-eks-addons:
    ✓ Committed: feat(cert-manager): add service deployment for bg-qa and bg-prod
    ✓ Pushed to origin/feat/PLAT-456-add-cert-manager
    ✓ PR created: https://github.com/boatsgroup/iac-eks-addons/pull/87
      Title: "PLAT-456: Add cert-manager service deployment"
```

### Step 10: Merge (you do this)

The command tells you the merge order:

```
╔════════════════════════════════════════════════╗
║    MERGE ORDER (important!)                    ║
╠════════════════════════════════════════════════╣
║                                                ║
║  1. FIRST: iac-eks-argocd PR #42               ║
║     (sets up permissions and discovery)        ║
║                                                ║
║  2. THEN:  iac-eks-addons PR #87               ║
║     (triggers ArgoCD to discover and deploy)   ║
║                                                ║
╚════════════════════════════════════════════════╝
```

After merging both PRs, ArgoCD automatically discovers the new `config.yaml`
and creates the deployment. No manual `kubectl apply` or deployment step needed.

### What just happened (behind the scenes)

1. `config.yaml` on `main` triggers the ApplicationSet's git file generator
2. ArgoCD creates an Application resource pointing to your overlay
3. The Application syncs the Helm chart with your environment-specific values
4. cert-manager pods start in the `cert-manager` namespace
5. The XIRSARole claim provisions an IAM role via Crossplane
6. cert-manager uses that role for DNS-01 challenge validation

You can verify the deployment:

```bash
argocd app get cert-manager-bg-qa        # Should show Synced + Healthy
kubectl get pods -n cert-manager          # Should show running pods
```

---

## Terminology

If you encounter unfamiliar terms in any Mobius doc, check the
[Glossary](glossary.md).

---

## Need More?

| I want to... | Read |
|-------------|------|
| Understand how the platform works | [Platform Overview](architecture/platform-overview.md) |
| See all available workflows | [Workflow Index](workflows/INDEX.md) |
| Navigate all documentation | [Docs Mind Map](ecosystem-start-here.md) |
| Troubleshoot an issue | [Troubleshooting](troubleshooting.md) |
| Look up a term | [Glossary](glossary.md) |
