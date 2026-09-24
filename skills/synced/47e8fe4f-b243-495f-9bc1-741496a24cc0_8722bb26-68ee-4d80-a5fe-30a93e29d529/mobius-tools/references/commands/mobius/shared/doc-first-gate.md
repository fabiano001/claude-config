<!-- MODULE_SUMMARY: Doc-first gate — checks whether docs exist in the target repo, extracts AWS resource dependencies from docs, cross-references against registered XRDs, and offers the appropriate document command if docs are missing. Used by migrate-ecs-service, add-service, validate-service, and debug-service. -->

## Doc-First Gate

Run this gate **before any intake, file generation, or cluster inspection** for the target service or repo.

### Step 1: Detect Documentation

Check for existing docs in the target repo:

```bash
# Check docs presence
ls <target-repo>/docs/ 2>/dev/null
ls <target-repo>/AGENTS.md 2>/dev/null
ls <target-repo>/docs/ARCHITECTURE.md 2>/dev/null
ls <target-repo>/docs/architecture/ 2>/dev/null
```

**Decision tree:**

| Docs state | Action |
|------------|--------|
| `docs/ARCHITECTURE.md` or `docs/architecture/` exists | Read it. Extract AWS deps (Step 2). Proceed. |
| `AGENTS.md` exists but no `docs/` | Read AGENTS.md for AWS hints. Warn: docs incomplete. Offer to generate (Step 3). Proceed anyway. |
| Neither exists | **STOP.** Offer documentation commands (Step 3) before proceeding. |

### Step 2: Extract AWS Dependencies From Docs

When docs exist, scan for AWS service mentions to identify dependencies beyond IRSA:

```bash
rg -i "appconfig|s3|sqs|sns|elasticache|redis|rds|dynamodb|kinesis|secretsmanager|eventbridge" \
  <target-repo>/docs/ --include="*.md" -l
```

For each AWS service found, map to platform resources:

| AWS Service | XRD Available | Action |
|-------------|---------------|--------|
| AppConfig | None | Add `appconfig:GetLatestConfiguration`, `appconfig:StartConfigurationSession` to XIRSARole |
| S3 | `s3-bucket` XRD | Check if claim exists in overlay; if not, offer to add claim |
| SQS / EventBridge | `sqs-eventbridge` XRD | Check if claim exists in overlay; if not, offer to add claim |
| Secrets Manager | `generated-aws-secret` XRD | Check if claim exists in overlay; if not, offer to add claim |
| ElastiCache / Redis | None | Flag for manual: no XRD exists. Add IAM + note in checklist. |
| RDS / Aurora | None | Flag for manual: no XRD exists. Add IAM + note in checklist. |
| DynamoDB | None | Flag for manual: no XRD exists. Add IAM + note in checklist. |
| Kinesis | None | Flag for manual: no XRD exists. Add IAM + note in checklist. |

**Claim existence check:**

```bash
# Check if a Crossplane claim already exists in the service overlay
rg 'kind: XS3Bucket|kind: XSqsEventBridge|kind: XGeneratedAwsSecret' \
  <service-repo>/argocd/<service>/base/ 2>/dev/null
```

Present a dependency summary before proceeding:

```
AWS Dependency Summary for <service>:
  ✅ IRSA (SSM)         — xirsarole.yaml present
  ⚠️  AppConfig         — no XRD; add appconfig IAM actions to XIRSARole
  ❌ S3 bucket          — s3-bucket XRD available; no claim found in overlay
  ❌ SQS + EventBridge  — sqs-eventbridge XRD available; no claim found in overlay

Action required before proceeding:
  1. S3 claim: add to argocd/<service>/base/ or confirm not needed
  2. SQS claim: add to argocd/<service>/base/ or confirm not needed
  3. AppConfig IAM: will be added to XIRSARole automatically

Reply:
  - "add claims" → generate claim files before continuing
  - "skip" → proceed without claims (flag in checklist)
  - "confirm not needed" for any item → remove from list
```

Wait for user response before proceeding.

### Step 3: Offer Documentation Commands (when docs missing)

Determine which document command to offer based on the repo structure:

```bash
# Detect repo type
ls <target-repo>/apps/ 2>/dev/null      # → monorepo with services
ls <target-repo>/libs/ 2>/dev/null      # → monorepo with libraries
ls <target-repo>/src/ 2>/dev/null       # → single service or library
cat <target-repo>/package.json 2>/dev/null | rg '"type"'
```

| Repo structure | Offer |
|----------------|-------|
| Has `apps/` directory | `/mobius:document-service` (service docs + api-reference) |
| Has `libs/` directory | `/mobius:document-library` (integration guide + cloud permissions) |
| Has both `apps/` + `libs/` (monorepo) | Offer both; document-service for apps, document-library for libs |
| Infrastructure repo (no apps/libs) | `/mobius:document-repo` (AGENTS.md + architecture docs) |
| Single service, no monorepo structure | `/mobius:document-service` |

**Before presenting the offer, check whether this repo is still
substantially an unmodified template scaffold** — documenting it now would
just describe the template, not the actual service:

```bash
# Cheap, deterministic signals of an unmodified scaffold (not exhaustive —
# add signals for other templates as they come up):
git -C <target-repo> log --oneline | wc -l   # ≤2-3 commits is suspicious
ls <target-repo>/server/handlers/v1/example.ts 2>/dev/null   # api-node-template's literal example handler, unrenamed
rg -l "ApiNodeTemplate|<insert-short-description-here>" <target-repo> 2>/dev/null   # leftover template placeholders
```

If the repo looks like an unmodified scaffold (very few commits AND
generic example files/placeholders still present), warn before offering
documentation instead of jumping straight to it:

```
⚠️  <repo> looks like it might still be a mostly-unmodified template
scaffold (only <N> commits, generic example handler still present) —
running /mobius:document-<type> now would describe the template's generic
structure, not <service-name>'s actual behavior.

Options:
  a) "document anyway" → proceed with the normal doc-first flow below
  b) "skip for now" → proceed without docs, same as "proceed anyway" (flag AWS dependencies as LOW confidence)
  c) "let me add real logic first" → pause here, resume this gate once the service has real code
```

Only fall through to the doc-missing offer below once this check has been
addressed (either the repo doesn't look like an unmodified scaffold, or the
user explicitly chose to proceed).

Present the offer:

```
⚠️  No docs found in <repo>.

Documentation is required before proceeding — docs reveal AWS dependencies
(AppConfig, S3, SQS, etc.) that cannot be reliably inferred from code alone.

Recommended:
  1. Run /mobius:document-<type> <repo> first (PR 1 — docs only)
  2. Use the generated docs to drive this command (PR 2 — actual changes)

Options:
  a) "document first" → I'll run /mobius:document-<type> now and pause this workflow
  b) "proceed anyway" → Continue without docs (AWS dependencies may be incomplete — flag all unknowns)
  c) "docs are here: <path>" → Point me to docs in a non-standard location
```

**If user chooses "document first":** Invoke the appropriate document command, then resume from the top of this gate after docs are generated.

**If user chooses "proceed anyway":** Continue, but:
- Mark all XRD dependency findings as `LOW` confidence
- Add a checklist item: "Verify AWS dependencies manually — docs were missing"
- Do NOT claim the migration/service is complete until docs are created
