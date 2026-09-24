---
name: migrate-ecs-ci-cd
description: Add EKS deploy/rollback secret passthrough to a repo's pr-command-dispatch workflow
argument-hint: <repo-name>
model: sonnet
---
<!-- This file is an AI agent instruction spec. -->


# Migrate ECS CI/CD: Add EKS Secret Passthrough

## Model Recommendation

> **Use a sonnet-tier model** (Claude `claude-sonnet-4-6` or OpenAI `o3-mini`).
>
> This is a straightforward, single-file change with clear validation criteria.
> No complex mapping or multi-repo coordination required. The agent adds 4 secrets
> to one workflow file and creates a PR.

This command adds EKS deploy/rollback secret passthrough to a repo's
`pr-command-dispatch.yml` workflow, enabling `/deploy-eks` and `/rollback-eks`
slash commands via `core-engineering-automation` v2.15.0.

---

## Canonical Rules

- Only modify the `secrets:` block in `pr-command-dispatch.yml` — nothing else.
- Validate that the repo is eligible (in CSV, marked `EKS Deploy Ready: Yes`, on `@v2`).
- Do not proceed if EKS secrets are already present (already migrated).
- Work is not complete until a PR exists with exactly 4 secret additions.

---

## Step 0: Input Validation

Accept `<repo-name>` argument (e.g., `api-node-atvs`).

### 0a: CSV Lookup

1. Load the EKS migration readiness CSV. Search in this order:
   - `mobius-tools/data/api-node-eks-migration-readiness.csv` (relative to workspace)
   - `/Users/spencer/GitHub/claude/mobius-tools/data/api-node-eks-migration-readiness.csv` (absolute fallback)
2. Find the row matching the `Repo Name` column

**Gate: CSV Match** — If repo not found, error:
```
❌ Repo "<repo-name>" not found in api-node-eks-migration-readiness.csv.

Available repos:
  - api-node-atvs
  - api-node-boats
  - ...
```

### 0b: EKS Deploy Ready Check

Check the `EKS Deploy Ready` column for the matched row.

**Gate: EKS Deploy Ready** — Must be `Yes`. If `No` or empty, error:
```
❌ Repo "<repo-name>" is not EKS deploy ready.
   EKS Deploy Notes: <value from EKS Deploy Notes column>

This repo must resolve its blockers before running this migration.
```

### 0c: Extract Repo URL

Extract the repo URL from the `URL` column. Derive the org/repo path (e.g., `boatsgroup/api-node-atvs`).

---

## Step 1: Fetch & Validate Workflow

Fetch the workflow file from the repo via GitHub API:

```bash
gh api repos/boatsgroup/<repo-name>/contents/.github/workflows/pr-command-dispatch.yml
```

### Gate: Workflow Exists

If 404, error:
```
❌ This repo does not have a pr-command-dispatch.yml workflow.
```

### Gate: Uses core-engineering-automation

Validate the `uses:` line references:
```
boatsgroup/core-engineering-automation/.github/workflows/node-api-command-processing.yml
```

If not found, error:
```
❌ Workflow does not use core-engineering-automation. Cannot migrate.
```

### Gate: On @v2

Validate the ref is `@v2`. If not (e.g., still on a branch ref or older tag), error:
```
❌ Workflow is not on @v2. Current ref: @<ref>. Update to @v2 before running this migration.
```

### Gate: Not Already Migrated

Check if `EKS_APP_ID` is already present in the secrets block. If present:
```
ℹ️ This repo already has EKS secrets configured. No changes needed.
```
Stop — no action required.

---

## Step 2: Report Eligibility

Display a summary before proceeding:

```
✅ Repo: <repo-name>
✅ CI Platform: GitHub Actions
✅ Workflow: pr-command-dispatch.yml found
✅ Automation ref: @v2
✅ EKS secrets: Not yet configured

Ready to migrate. Proceeding...
```

---

## Step 2.5: JIRA Ticket Prompt

> Reference: `docs/workflows/shared/jira-integration.md` § Pre-Branch Ticket Prompt

Before creating a branch, prompt for a JIRA ticket:

```
Before we begin, is there a Jira ticket for this CI/CD migration?

1. **Yes, I have a ticket** → Enter ticket ID (e.g., DEVOPS-123)
2. **No, create one for me** → I'll create a ticket first
3. **No ticket needed** → Skip JIRA (branch will use repo name only)
```

Store as `jira_ticket_id` (e.g., `DEVOPS-5523` or `null`). This value flows into:
- Branch name in Step 3
- PR title and body in Step 6

---

## Step 3: Clone & Branch

1. Check if the repo exists locally at `../<repo-name>` relative to the current working directory.
   - If yes, use the local copy. Ensure on `main` and pull latest.
   - If no, clone: `gh repo clone boatsgroup/<repo-name> /tmp/<repo-name>` and use that path.
2. Determine branch name:
   - With JIRA: `feat/<jira_ticket_id>-migrate-ci-cd-<repo-name>` (e.g., `feat/DEVOPS-5523-migrate-ci-cd-api-node-atvs`)
   - Without JIRA: `feat/migrate-ci-cd-<repo-name>` (e.g., `feat/migrate-ci-cd-api-node-atvs`)
3. Create branch: `git checkout -b <branch-name>`

**If branch already exists**, ask the user:
```
Branch "<branch-name>" already exists.

1. Use existing branch
2. Choose a different branch name
```

---

## Step 4: Apply Changes

Add the 4 EKS/ArgoCD secrets to the `secrets:` block in `.github/workflows/pr-command-dispatch.yml`.

### Secrets to Add

```yaml
      EKS_APP_ID: ${{ secrets.EKS_APP_ID }}
      EKS_APP_PRIVATE_KEY: ${{ secrets.EKS_APP_PRIVATE_KEY }}
      ARGOCD_AUTH_TOKEN: ${{ secrets.ARGOCD_AUTH_TOKEN }}
      ARGOCD_SERVER: ${{ secrets.ARGOCD_SERVER }}
```

### Placement Rule

Insert after the existing `secrets:` entries (after the last existing secret line, e.g., after `ARTIFACTORY_TOKEN`, or at the end of the secrets block). Preserve existing indentation and formatting exactly.

### Critical Constraint

Do **NOT** modify any other part of the file. No changes to `runner-size`, `audit-level`, the `with:` block, or anything else. Only add the 4 new secrets.

---

## Step 5: Validate Change

1. Verify the modified file is valid YAML (parse it)
2. Verify only the secrets block changed: `git diff` should show only additions of the 4 new lines
3. Verify all 4 new secrets are present: `EKS_APP_ID`, `EKS_APP_PRIVATE_KEY`, `ARGOCD_AUTH_TOKEN`, `ARGOCD_SERVER`
4. Verify no other lines were modified or removed

If any check fails, revert and retry the edit.

---

## Step 6: Commit, Push, PR

1. Stage the file:
   ```bash
   git add .github/workflows/pr-command-dispatch.yml
   ```

2. Commit:
   ```bash
   git commit -m "feat: add EKS deploy/rollback secret passthrough"
   ```

3. Push:
   ```bash
   git push -u origin <branch-name>
   ```

4. Create PR:
   ```bash
   gh pr create \
     --title "feat: add EKS deploy/rollback command dispatch [<JIRA_TICKET_ID>]" \
     --body "$(cat <<'EOF'
   ## Summary

   - Add `EKS_APP_ID`, `EKS_APP_PRIVATE_KEY`, `ARGOCD_AUTH_TOKEN`, and `ARGOCD_SERVER`
     secrets to `pr-command-dispatch.yml` workflow
   - Enables `/deploy-eks` and `/rollback-eks` slash commands via
     `core-engineering-automation` v2.15.0

   ## Test plan

   - [ ] Verify CI passes
   - [ ] After merge, test `/deploy-eks bg-qa` from Actions tab

   ## JIRA

   <JIRA_TICKET_ID>
   EOF
   )"
   ```

   Omit `[<JIRA_TICKET_ID>]` from the title and `## JIRA` from the body if no ticket.

If push fails, report the error and suggest manual resolution. Do not force-push.

---

## Step 7: Report Result

```
✅ Migration complete for <repo-name>

Branch: <branch-name>
JIRA: <JIRA_TICKET_ID> (or "none")
PR: <pr-url>

Next steps:
1. Review and merge the PR
2. Configure org-level secrets (EKS_APP_ID, EKS_APP_PRIVATE_KEY) if not already done
3. Configure environment secrets (ARGOCD_AUTH_TOKEN, ARGOCD_SERVER) for bg-qa/bg-prod
4. Test with /deploy-eks bg-qa from the Actions tab
```

---

## Error Handling

| Condition | Behavior |
|-----------|----------|
| Repo not in CSV | Error with message, list available repos |
| Not EKS Deploy Ready | Error: show blocker notes from CSV |
| No `pr-command-dispatch.yml` | Error: "No workflow file found" |
| Not on `@v2` | Error: "Workflow ref is `@{ref}`, must be `@v2` first" |
| Already has EKS secrets | Info: "Already migrated, no changes needed" |
| Branch already exists | Ask user: use existing or choose different name |
| Push fails | Report error, suggest manual resolution |

---

## Reference Files

| File | Role |
|------|------|
| `api-node-boats/.github/workflows/pr-command-dispatch.yml` | Reference implementation (the "golden" change) |
| `api-node-atvs/.github/workflows/pr-command-dispatch.yml` | Example target (typical baseline) |
| `mobius-tools/data/api-node-eks-migration-readiness.csv` | Source of truth for repo eligibility and EKS readiness |

---

## Related Commands

| Command | Relationship |
|---------|-------------|
| `/mobius:migrate-ecs-service` | Migrates the ECS runtime (Helm charts, overlays, ArgoCD wiring). Run that first, then this command to enable CI/CD. |
| `/mobius:validate-service` | Validates the EKS service config after `migrate-ecs-service`. Independent of CI/CD workflow changes. |

---

## Anti-Patterns

| Anti-Pattern | Why It Is Forbidden |
|--------------|---------------------|
| Modifying anything outside `secrets:` block | Causes unrelated behavioral changes to the workflow |
| Skipping CSV validation | Repo may not be eligible (Jenkins, decommissioned, etc.) |
| Proceeding when not on `@v2` | Older workflow versions don't support EKS commands |
| Re-adding secrets that already exist | Creates duplicate entries and broken YAML |
| Force-pushing | Overwrites others' work on the branch |
