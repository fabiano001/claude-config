---
name: add-collector
description: Scaffold a new collector + Prometheus exporter pair that reads from an external API, writes to S3, and exposes metrics on scrape
argument-hint: <source-name> [--bucket <s3-bucket>]
model: opus
---
<!-- This file is an AI agent instruction spec. For human documentation, see docs/engineer-guide.md -->

# Scaffold a Collector + Exporter Pair

## Model Recommendation

> **Use an opus-tier model** (Claude `claude-opus-4-6`).
>
> This command requires inferring metric structure from an arbitrary sample
> payload (Phase 2), choosing between aggregate-at-collect-time and raw
> passthrough based on API cost tradeoffs (Phase 1), and generating two
> coordinated files that must stay consistent with each other. Weaker models
> may misjudge which fields are safe as Prometheus labels or miss the
> reasoning behind the collection-strategy choice.

Generates two files that work together: a **collector** (external API → S3,
run on a schedule) and an **exporter** (S3 → Prometheus metrics, run as a
long-lived scrape target). Mirrors the existing NINJIO and Sublime pairs in
`ops-command-center`.

## Architecture Context

```
Scheduled collector run (GitHub Actions cron)
    |
    v
Paginate external API --> write raw or aggregated JSON to S3 (dated key)
                                                                  |
                                                                  v
                                          Exporter reads latest key on every scrape
                                                                  |
                                                                  v
                                          Custom Collector.collect() yields GaugeMetricFamily
                                                                  |
                                                                  v
                                          Prometheus scrapes /metrics
```

---

## Phase 0 — Preflight

> **Step 0a** (Git): Verify `gh auth status`, clean working tree
> (`git status --porcelain`), and current branch. If not on `main`, ask user
> to use current branch or start fresh from main. Reference:
> `docs/workflows/shared/multi-repo-git-workflow.md` § Preflight Checks.

> **Step 0b** (JIRA): Prompt for JIRA ticket ID (strongly encouraged).
> Options: (1) enter ticket ID, (2) create one, (3) skip. Store as
> `jira_ticket_id` — flows into branch name, commit footer, and PR title.

## Phase 1 — Intake

| Question | Options | Drives |
|---|---|---|
| Source name | free text | filenames, env var prefix, metric name prefix |
| Auth style | API-key header / Bearer token | `HEADERS` construction |
| Pagination style | page-number + `has_next` / offset + short-page-stop / cursor-based | `iter_pages()` body |
| Collection strategy | aggregate-at-collect-time / raw passthrough — **no default, ask explicitly** | whether `main()` pre-aggregates before writing |
| Sample JSON payload | file path or pasted sample | Phase 2 discovery input |
| Multi-day history needed for any metric? | yes/no + which fields | whether to scaffold the `(key, value)` cache pattern |

**Collection strategy — decide per source, don't default.** Ask: *does this
source require expensive per-item follow-up calls to get useful data?* If
yes, aggregate at collect time (dedup by `id` before writing to S3). If no,
write raw passthrough — cheaper to store and preserves flexibility for
metrics that need to re-read multiple days of history later.

**Error-body logging is always included** in generated `get()` functions
(logs response body on 4xx/5xx before raising) — no intake question needed,
since there's no tradeoff to weigh.

## Phase 2 — Discovery

From the Phase 1 sample payload, identify field *shapes* — this logic is
domain-agnostic and applies the same way regardless of what the source API is
for.

Never assume a field's business meaning — only classify its *shape*. A field
named `severity` or `tier` might mean something specific to this source, but
its shape (a small, repeated set of string values) is all this phase needs to
identify.

### Step 2.1: List-Shaped Fields

Scan the sample payload for array fields. For each one, record:
- `field_path` — dotted path to the field (e.g. `orders`, `scan_summary.hosts`)
- `item_count` — length in the sample
- `has_id_field` — whether items in the array contain an `id`-like key

### Step 2.2: Categorical Fields

Within any list-shaped field found in Step 2.1, scan item keys for fields
with a small, repeated set of string values (a status, type, tier, category).
For each one, record:
- `field_path`
- `distinct_values_in_sample[]`
- `parent_list` — which Step 2.1 field this belongs to

### Step 2.3: Ratio Candidates

Identify pairs of counts where one is clearly a subset or portion of the
other (e.g. `items_with_findings` / `items_scanned`). For each pair, record:
- `numerator_field_path`
- `denominator_field_path`
- `requires_zero_guard: true` — always true; any count can legitimately be
  zero, and unguarded division by zero crashes the whole exporter, not just
  that one metric

### Step 2.4: Dedup Requirements

Only relevant if Phase 1 selected aggregate-at-collect-time. For each
list-shaped field with `has_id_field: true`, record:
- `field_path`
- `dedup_key` — the id-like field name found

### Discovery Output Schema

This is the handoff contract into Phase 3. Persist as a structured object,
not prose:

```yaml
phase2_discovery:
  list_fields:
    - field_path: string
      item_count: integer
      has_id_field: boolean

  categorical_fields:
    - field_path: string
      parent_list: string
      distinct_values_in_sample: [string]

  ratio_candidates:
    - numerator_field_path: string
      denominator_field_path: string
      requires_zero_guard: true

  dedup_requirements:
    - field_path: string
      dedup_key: string
```

Phase 3 reads this object directly to build the panel list — it should not
need to re-scan the sample payload.

## Phase 3 — Present Plan

Read the `phase2_discovery` object from Phase 2 and render it into a plan
for the engineer to approve before any code is generated.

```
Source: {source_name}
Auth: {api-key header | bearer token}
Pagination: {style}
Collection strategy: {raw passthrough | aggregate-at-collect}

Collector: collectors/{source_name}/{source_name}_collector.py
  Writes to: s3://{bucket}/{source_name}/{date}.json
  {if aggregate-at-collect-time: "Dedups by: " + each dedup_requirements[].dedup_key}

Exporter: collectors/{source_name}/{source_name}_exporter.py
  Mandatory: {source_name}_scrape_success, {source_name}_data_age_seconds

  Count gauges (from list_fields):
    {source_name}_{field_path}_total  — for each entry in list_fields

  Breakdown gauges (from categorical_fields):
    {source_name}_{parent_list}_by_{field_path}{{{field_path}="..."}}
    — for each entry in categorical_fields

  Ratio gauges (from ratio_candidates):
    {source_name}_{derived_name}_ratio  — {numerator_field_path} / {denominator_field_path}
    (zero-denominator guarded)

  Caching: {yes, N-day pattern — only if Phase 1 flagged multi-day history | no}

Approve this plan? (yes / edit / start over)
```

If the engineer selects **edit**, allow field-level overrides — e.g. rename a
gauge, drop a candidate field from the plan, or mark a categorical field as
"skip, too high-cardinality" (this feeds forward into Phase 4's cardinality
check).

Once approved, this becomes the **locked plan** — Phase 6 generates code only
from what's in this plan, nothing improvised.

## Phase 4 — Pre-Generation Validation (HARD GATE)

Run against the approved Phase 3 plan. All Error-severity checks must pass
before Phase 5 (Branch Gate) begins. If any Error fails, return to Phase 3
for plan edits rather than auto-fixing.

| ID | Check | Requirement | Severity |
|---|---|---|---|
| COL-001 | Health metrics present | Plan includes `{source}_scrape_success` and `{source}_data_age_seconds` | Error |
| COL-002 | Success always yielded | Generated `collect()` yields the success metric on both the happy path and the failure path | Error |
| COL-003 | Ratio safety | Every ratio metric has a zero-denominator guard | Error |
| COL-004 | Env var naming | Env vars are uppercase (`S3_BUCKET`, `<SOURCE>_API_KEY`) | Warning |
| COL-005 | No fabrication on empty | Collector writes a valid empty result on an empty API response — never fakes data | Error |
| COL-006 | Cardinality safety | Every label field is backed by a small, bounded set of values — no free-text or unbounded fields become labels | Warning |

## Phase 5 — Branch Creation Gate (HARD GATE)

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` — this
> command only touches the single repo it's run in, so only the Preflight
> Checks, Branch Creation Gate, and Commit Pattern sections apply. The
> multi-repo-specific steps (PR ordering, "Merge Order" sections) do not.

This phase MUST succeed before Phase 6 begins. No file generation until the
branch exists.

If on `main`: pull latest, then create a feature branch.
- With JIRA: `feat/<jira_ticket_id>-add-collector-<source_name>`
- Without JIRA: `feat/add-collector-<source_name>`

If the engineer chose to keep an existing branch in Phase 0, skip creation
and use that branch.

```bash
git checkout -b <branch-name>
git branch --show-current   # Verify
```

If the branch name already exists, offer: (a) switch to it and continue, or
(b) choose a different name.

```
Branch Gate Status:
  ✅ <repo>   → feat/DEVOPS-1234-add-collector-proofpoint

Proceeding to code generation.
```

## Phase 6 — Generate

### Step 6.1: Collector

Generate `collectors/{source_name}/{source_name}_collector.py`.

**`get()` wrapper** — always includes error-body logging (per Phase 1 decision):

```python
def get(path, params=None):
    response = requests.get(
        f"{base_url}{path}",
        headers=HEADERS,
        params=params or {},
        timeout=(5, 30),
    )
    if response.status_code >= 400:
        print(f"Error response body: {response.text[:500]}")
    response.raise_for_status()
    time.sleep(REQUEST_DELAY_SECONDS)
    return response.json()
```

**Auth** — per Phase 1 selection:
- API-key header: `HEADERS = {"Accept": "application/json", "<HeaderName>": <SOURCE>_API_KEY}`
- Bearer token: `HEADERS = {"Accept": "application/json", "Authorization": f"Bearer {<SOURCE>_API_KEY}"}`

Env var is always uppercase (`<SOURCE>_API_KEY`), per COL-004 — even though
the two existing real examples use lowercase, new collectors should not
repeat that.

**`iter_pages()`** — per Phase 1 pagination selection (page+has_next /
offset+short-page-stop / cursor-based).

**`main()`** — per Phase 1 collection strategy:
- Raw passthrough: write each fetcher's result directly into the output dict
- Aggregate-at-collect-time: dedup by the `dedup_key` from each
  `dedup_requirements[]` entry (Phase 2 schema) before writing

Always writes to `s3://{bucket}/{source_name}/{date}.json`, matching the
dated-key convention from both real collectors.

Per COL-005: if an endpoint returns an empty result, write the valid empty
shape (`{"message_groups": []}`, `[]`, etc.) — never fabricate placeholder
values.

### Step 6.2: Exporter

Generate `collectors/{source_name}/{source_name}_exporter.py`.

**`latest_key()` / `load_latest()`** — copied exactly as-is; confirmed
identical across both real exporters, no per-source variation needed:

```python
def latest_key(s3):
    latest = None
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=S3_PREFIX):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith(".json") and (latest is None or key > latest):
                latest = key
    return latest


def load_latest(s3):
    key = latest_key(s3)
    if key is None:
        raise FileNotFoundError(f"no objects under s3://{S3_BUCKET}/{S3_PREFIX}")
    obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
    return json.loads(obj["Body"].read()), key, obj["LastModified"]
```

**Custom `Collector` class** — `collect()` as a generator, matching the shape
confirmed in both real exporters:

1. Yield `{source}_scrape_success` first — `0` and early return on any
   exception from `load_latest()` (COL-002)
2. For each `list_fields[]` entry (Phase 2 schema): a count gauge
   `{source}_{field_path}_total`
3. For each `categorical_fields[]` entry not marked "skip" in Phase 3: a
   labeled breakdown gauge, one series per distinct value seen at scrape time
   (not just the values from the Phase 2 sample — the real data can have
   values the sample didn't)
4. For each `ratio_candidates[]` entry: a ratio gauge with the zero-guard
   pattern (COL-003):
   ```python
   def some_ratio(numerator, denominator):
       d = len(denominator or [])
       if not d:
           return 0.0
       return len(numerator or []) / d
   ```
5. If Phase 1 flagged multi-day history needed: a `(key, value)` tuple cache
   on `__init__`, checked before recomputing — only recompute when the S3 key
   changes, matching Sublime's `_blocked_7d_cache` pattern
6. `{source}_data_age_seconds` — seconds since `last_modified`
7. Yield `{source}_scrape_success = 1` last, on the success path

**`main()`** — standard WSGI server boilerplate, identical shape to both real
exporters (`CollectorRegistry`, `make_wsgi_app`, `make_server` on
`LISTEN_PORT`).

### Step 6.3: README

Generate `collectors/{source_name}/README.md`, per `CONTRIBUTING.md`'s
command-spec conventions (what it does, inputs, outputs, usage example):

```markdown
# {source_name} Collector + Exporter

## What it does

Collects data from {source_name}'s API on a schedule and writes it to S3.
A separate exporter reads the latest S3 object on every Prometheus scrape
and exposes it as metrics.

## Inputs

- `{SOURCE}_API_KEY` — API credential (required)
- `S3_BUCKET` — target bucket (required; no hardcoded default — set this
  explicitly for your environment)
- `S3_PREFIX` — object key prefix (default: `{source_name}/`)
- `LISTEN_PORT` — exporter HTTP port (default: `8000`)

## Outputs

- S3 object: `s3://{bucket}/{source_name}/{YYYY-MM-DD}.json`
- Prometheus metrics at `/metrics`:
  - `{source_name}_scrape_success`
  - `{source_name}_data_age_seconds`
  - {list of generated panel gauges from the approved Phase 3 plan}

## Usage

```bash
# Run the collector once (e.g. on a schedule)
python3 {source_name}_collector.py

# Run the exporter (long-lived, for Prometheus to scrape)
python3 {source_name}_exporter.py
```
```

### Step 6.4: GitHub Actions AWS Access (out of scope — defer to OIDC pattern)

This collector needs a GitHub Actions workflow with AWS access to write to
S3. Provisioning that access (the `XGitHubOIDCRole` Crossplane claim, any
required ArgoCD project whitelist entry, and the GitHub OIDC provider itself
if one doesn't already exist for the AWS account) is its own multi-repo,
ArgoCD/Crossplane-dependent process — out of scope for this command to
generate.

Add this note to the generated README instead:

```markdown
## Setup: AWS Access

This collector needs a GitHub Actions workflow with permission to write to
S3. If this project doesn't already have a working `XGitHubOIDCRole` claim
and workflow, see the mobius-tools GitHub Actions OIDC workflow guide
(reference once published) rather than provisioning this by hand.
```

Do not attempt to generate Crossplane claims, ArgoCD project whitelist
entries, or Terraform for AWS access as part of this command.

## Phase 7 — Validate

Before Phase 8, confirm the generated code actually works.

1. **Test-run the collector** with output written to a local file
   (`sample_output.json`, matching how NINJIO's collector was originally
   validated before it was switched to writing to S3) instead of S3 —
   confirm the real API calls succeed and the output JSON matches the shape
   from the approved Phase 3 plan.
2. **Run the exporter's `collect()`** against that local JSON file (or a
   fixture matching its shape) — confirm every gauge from the approved plan
   registers and yields a value.
3. Once local validation passes, run the collector once for real against
   the actual S3 bucket to confirm the full path works end-to-end.
4. **Lint** the generated files.

Present a Validation Summary before proceeding to Phase 8.

## Phase 8 — Commit, Push, PR

> Reference: `docs/workflows/shared/multi-repo-git-workflow.md` — Commit
> Pattern and Push + PR Pattern sections (single-repo case; PR ordering
> steps don't apply).

1. Stage all generated files (collector, exporter, README) in one commit.
2. Generate a conventional commit message from the actual diff, following
   the doc's Step C3 format. Present it for approval before committing.
3. Push the branch, open a PR with a description covering what was
   generated (source name, gauges, collection strategy) and the JIRA ticket
   if one exists.
4. Return the PR URL.

---

## Why Summary

> **Module**: Read `shared/why-summary.md` and `shared/repo-roles.md`, then
> generate the Why Summary using the context hints below.

**Command type**: generative

**Context hints**:
- "Impact opener" → new collector/exporter pair scaffolded for {source_name}
- "What was accomplished" → collector writes via {chosen strategy}, exporter
  exposes {N} gauges plus the two mandatory health metrics
- "Why it matters" → new sources onboard without re-deriving the S3-polling
  exporter pattern from scratch
- "What happens next" → deploy the collector on a schedule, deploy the
  exporter as a scrape target, verify `{source}_scrape_success == 1` after
  the first run
