# Why Summary — Output Format Guide

This module defines the "WHY THIS MATTERS" section that every command appends
to its output after execution completes. The goal is to explain changes in
plain language for developers who may not have deep experience with the platform.

**Audience:** Engineers who may not know Kubernetes, ArgoCD, Crossplane, Helm,
or Terraform. Write for someone who asks "wtf does the helm stuff do?"

---

## When to Generate

Generate a Why Summary at the end of every command execution EXCEPT:
- `help` (navigation only — no execution result)
- Command was interrupted or failed before completing any action
- User explicitly asks to skip it

---

## Output Format

```
───────────────────────────────────────────
WHY THIS MATTERS
───────────────────────────────────────────

<One-sentence impact opener with a concrete number or outcome.>

What was accomplished:
  • <bullet 1>
  • <bullet 2>
  • <bullet 3 if needed>

Changes by repository:

  <repo-name> — <one-line role>
    <2-3 sentence plain-language description of what this repo is>
    ▸ <specific change #1 and why it was made>
    ▸ <specific change #2 and why it was made>

  <repo-name> — <one-line role>
    <2-3 sentence plain-language description of what this repo is>
    ▸ <specific change #1 and why it was made>
    ▸ <specific change #2 and why it was made>

Why it matters:
  • <business/operational significance bullet 1>
  • <business/operational significance bullet 2>

What happens next:
  • <next step 1 — with plain-language explanation of WHY this order>
  • <next step 2>
  • <verification command if applicable>

───────────────────────────────────────────
```

---

## Section Header by Command Type

The "Changes by repository" header adapts based on what the command does:

| Command Type | Section Header |
|-------------|----------------|
| Generative | "Changes by repository:" |
| Diagnostic | "Repos involved:" |
| Validation | "Repos checked:" |
| Analysis | "Repos in the blast radius:" |

---

## Hard Rules

1. **Plain language only.** No jargon. Don't say "ApplicationSet," say "discovery rule that tells the deployment system to watch for your service." Don't say "IRSA claim," say "AWS permissions so the service can securely access its database."

2. **Full explanation for every repo.** Every repository touched by the command gets the complete treatment: repo name, one-line role, 2-3 sentence plain-language description, and specific change bullets. This applies even when 5-6 repos are involved. Never condense repos into one-liners or "also changed" summaries. The whole point is that developers unfamiliar with the platform need to understand what EACH repo does.

3. **Lead with a concrete number.** The impact opener must include a specific number: "deployed to 2 environments," "affects 13 repos," "3 checks failed," "found 1 root cause with 2 cascading failures."

4. **Explain merge order in plain terms.** When multiple PRs need merging, explain WHY the order matters: "Merge the deployment control center PR first — the system needs to know about your service before the configuration can be deployed."

5. **Use causal chains for diagnostics.** When explaining failures, use the → arrow pattern: "wrong identity → blocked AWS access → missing database connection → service crashes on startup."

6. **"Why it matters" is about outcomes, not implementation.** Don't say "ArgoCD sync policy was configured." Say "Engineers can now ship features by pushing code — no manual deployment tickets needed."

7. **Repo descriptions come from `shared/repo-roles.md`.** Read that file for the canonical plain-language description of each repo. Adapt the description slightly to fit the context of what the command did, but keep the same tone and level of simplicity.

---

## Complete Example: Generative Command (`add-service`)

```
───────────────────────────────────────────
WHY THIS MATTERS
───────────────────────────────────────────

A new payment processing service is now configured to deploy
automatically to 2 environments across 2 repositories.

What was accomplished:
  • The payments service (api-node-payments) is wired for automatic
    deployment to QA and production.
  • AWS permissions were configured so the service can securely access
    its database credentials without manual key management.
  • High-availability protections were added: the service is spread
    across multiple servers and protected during maintenance windows.

Changes by repository:

  helm-charts — where the service's configuration lives
    This repo holds the actual settings for your service: what container
    image to run, how much CPU and memory it needs, which environments
    to deploy to, and how to connect to cloud resources like databases.
    Engineers own their service configurations here.
    ▸ Created the base configuration: chart version, resource limits,
      security settings, and health check endpoints
    ▸ Created QA-specific settings (lower resources, QA database endpoint)
    ▸ Created production-specific settings (higher resources, production
      database endpoint, stricter availability rules)
    ▸ Added AWS identity permissions so the service can access its
      database credentials from Secrets Manager

  iac-eks-argocd — the deployment control center
    This repo is the brain of the deployment system. It knows about every
    service and who has permission to deploy what. Services can't be
    deployed until they're registered here — think of it like a phone
    directory.
    ▸ Created the discovery rule that tells the deployment system to
      watch for this service's configuration files and deploy them
      automatically when they change
    ▸ Updated project permissions to allow deployments to the
      api-node-payments namespace

Why it matters:
  • Engineers can now ship payment features by pushing code — no manual
    server configuration or deployment tickets needed.
  • The service is protected against infrastructure failures: if a
    server is replaced during maintenance, traffic automatically
    shifts to other copies of the service with zero downtime.

What happens next:
  • Merge the iac-eks-argocd PR first — the deployment system needs
    to know about the service before the configuration can be deployed.
  • Then merge the helm-charts PR — this triggers the actual deployment.
  • Within 5 minutes of both PRs merging, the service is live.
  • Verify with: /mobius:debug-service api-node-payments --env bg-qa

───────────────────────────────────────────
```

---

## Complete Example: Diagnostic Command (`debug-service`)

```
───────────────────────────────────────────
WHY THIS MATTERS
───────────────────────────────────────────

Found 1 root cause of the payments service outage, causing
2 cascading failures across 1 environment.

What was accomplished:
  • Identified that the service's AWS identity was configured for the
    wrong environment, blocking access to database credentials.
  • Traced the full failure chain: wrong identity → blocked AWS access
    → missing database connection → service crashes on startup.

Repos involved:

  helm-charts — where the service's configuration lives
    This repo holds the settings for your service. The identity
    configuration in the production environment was pointing to QA's
    security provider instead of production's.
    ▸ Fix needed: Update the identity provider reference in the
      production settings to match the production cluster

  iac-eks-argocd — the deployment control center
    This repo controls deployment permissions. The deployment
    permissions may need updating to explicitly allow the service's
    source repo.
    ▸ Verify: Confirm project permissions include the helm-charts repo

Why it matters:
  • Payment processing has been degraded for approximately 4 hours,
    affecting the checkout flow for end users.
  • Only production is affected — QA is healthy, which is why this
    wasn't caught during testing.

What happens next:
  • Apply the helm-charts fix to correct the identity config.
  • The service will automatically redeploy within ~5 minutes of merge.
  • Monitor with: /mobius:debug-service api-node-payments --env bg-prod

───────────────────────────────────────────
```

---

## Complete Example: Validation Command (`validate-service`)

```
───────────────────────────────────────────
WHY THIS MATTERS
───────────────────────────────────────────

Audited the payments service and found 3 issues that would cause
problems in production.

What was accomplished:
  • Ran 47 checks across structure, security, scheduling, and
    networking categories.
  • Found 2 failures (must fix before deploying) and 1 warning
    (recommended improvement).

Repos checked:

  helm-charts — where the service's configuration lives
    This repo holds the service settings that were audited. The
    checks look at whether the service is configured correctly for
    production: enough resources, proper security, health checks, etc.
    ▸ FAIL: The service doesn't have enough copies configured to
      survive a server going down during maintenance
    ▸ FAIL: Security settings allow the service to run with more
      permissions than it needs (principle of least privilege)
    ▸ WARN: Health check endpoints for "is the service alive?" and
      "is the service ready for traffic?" are the same — they should
      be different so the system can distinguish between the two

Why it matters:
  • The 2 failures would cause downtime during routine maintenance
    and leave the service running with unnecessary permissions.
  • Fixing these before merging prevents production incidents.

What happens next:
  • Fix the 2 failures in the helm-charts PR.
  • Re-run: /mobius:validate-service api-node-payments --service-repo ../helm-charts
  • The warning is optional but recommended for operational clarity.

───────────────────────────────────────────
```

---

## Complete Example: Analysis Command (`trace-impact`)

```
───────────────────────────────────────────
WHY THIS MATTERS
───────────────────────────────────────────

Changes to this repo would affect 13 other repositories — this is
a CRITICAL blast radius.

What was accomplished:
  • Mapped all direct and transitive dependencies for iac-eks-argocd.
  • Identified 5 repos directly affected and 8 more affected through
    dependency chains.

Repos in the blast radius:

  iac-eks-crossplane — the cloud resource provisioning system
    This repo manages automatic creation of cloud resources (databases,
    storage, permissions). It depends on the deployment control center
    to know where to provision resources.
    ▸ Directly affected: changes to deployment config could break
      cloud resource provisioning across all clusters

  iac-eks-addons — where platform service configurations live
    This repo holds configurations for platform services (monitoring,
    DNS, certificates). It relies on the deployment system to actually
    deploy those services to clusters.
    ▸ Directly affected: deployment system changes could prevent
      platform services from being deployed or updated

  crossplane-xrd-irsa-role — self-service AWS permissions template
    Lets services request AWS permissions. Depends on the cloud resource
    system, which depends on the deployment control center.
    ▸ Transitively affected via iac-eks-crossplane: if the cloud
      resource system breaks, services can't get AWS permissions

Why it matters:
  • This repo is in the "core" tier — the most impactful part of the
    platform. Changes here cascade to nearly every other repo.
  • Any mistake could affect all services across all clusters.

What happens next:
  • Before making changes, read the internal documentation for this
    repo AND all 5 directly-affected repos.
  • Consider a staged rollout: test in QA cluster before production.
  • After changes, verify with: /mobius:validate-graph

───────────────────────────────────────────
```

---

## Anti-Patterns

| Bad | Good |
|-----|------|
| "Updated ApplicationSet in iac-eks-argocd" | "Registered the service with the deployment system so it deploys automatically" |
| "Added IRSA claim for api-node-payments" | "Configured AWS permissions so the service can securely access its database" |
| "Modified kustomization.yaml in overlay" | "Created environment-specific settings for QA (lower resources, QA database)" |
| "Configured podAntiAffinity" | "Spread the service across multiple servers so it stays running during maintenance" |
| "Also changed: iac-eks-observability, terraform-stack-monitoring-ng" | Give each repo the full explanation — never condense |
| "The ArgoCD sync policy was set to automated with prune and selfHeal" | "Changes to the service's settings are now deployed automatically within 5 minutes" |
