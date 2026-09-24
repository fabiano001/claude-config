# Operational Runbooks

Step-by-step procedures for the most common Mobius platform incidents.

Each runbook follows the same structure: symptoms, quick triage, step-by-step resolution,
and permanent fix path. Temporary `kubectl` commands unblock the immediate problem;
permanent fixes always go through IaC.

## Runbooks

| Runbook | When to use |
|---------|-------------|
| [ArgoCD Sync Stuck or Failed](argocd-sync-stuck.md) | Application shows OutOfSync, SyncFailed, or sync hangs indefinitely |
| [Crossplane Claim Not Ready](crossplane-claim-not-ready.md) | XRD claim stuck in not-ready state, managed resources have errors |
| [Service Unreachable](service-unreachable.md) | 502/503 errors, DNS not resolving, traffic not reaching pods |
| [IRSA AccessDenied](irsa-access-denied.md) | Pods getting AccessDenied, NoCredentialProviders, or STS errors |
| [ApplicationSet Not Discovering](applicationset-not-discovering.md) | config.yaml merged but ArgoCD Application never created |

## When to Use These vs. `/mobius:debug-service`

These runbooks are for **manual, step-by-step** investigation when:
- You want to understand what's happening at each layer
- You're debugging in an environment without the command pack installed
- You need to hand off investigation steps to another engineer

For **automated** diagnosis, run:
```
/mobius:debug-service <service-name> --env <env>
```
The debug command runs these same checks automatically and produces a structured report.

## General Principles

1. **Read-only first.** Gather evidence before making changes.
2. **Temporary vs. permanent.** `kubectl` commands unblock now; IaC changes are the real fix.
3. **Merge order matters.** Permissions/wiring repos (`iac-eks-argocd`) merge before content repos.
4. **Re-validate after fixing.** Run `/mobius:validate-service` or re-run diagnostics to confirm.

## Source Material and Improvement

These runbooks are derived from the `/mobius:debug-service` command spec
(`commands/mobius/debug-service.md`), which encodes debugging patterns developed
through real platform operations with Claude Code and Codex.

**To improve a runbook after an incident:**

1. Walk the runbook during the incident — note what's missing or wrong
2. Edit the runbook with corrections (add steps, fix commands, reorder)
3. If the fix also applies to automated debugging, update the `debug-service.md`
   command spec to match
4. Open a PR with the changes — conventional commit: `docs(runbooks): <what changed>`
