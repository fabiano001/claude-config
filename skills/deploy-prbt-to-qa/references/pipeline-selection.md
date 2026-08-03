# Pipeline selection (Step 1 detail)

## 1. List candidates

```bash
aws codepipeline list-pipelines --profile bg-qa --region us-east-1 \
  --query "pipelines[].name" --output text
```

Filter the result to names matching `^portal-react-boattrader-[0-9]{2}$` (currently `-01` through `-06`). **Explicitly exclude** the bare `portal-react-boattrader` name (no suffix) and anything else that isn't a pure `-NN` suffix (e.g. don't accidentally match a differently-shaped name). Do not hardcode the list of six — always list live, since a 7th environment could be provisioned later.

## 2. Get each candidate's last-usage timestamp

For each candidate `portal-react-boattrader-NN`:

```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name "portal-react-boattrader-NN" \
  --profile bg-qa --region us-east-1 \
  --max-items 1 --output json
```

Take `pipelineExecutionSummaries[0].startTime` as `LAST_USED_NN`. The API returns executions newest-first, so index `[0]` is always the most recent.

**Edge case — zero executions ever:** if `pipelineExecutionSummaries` is empty, this pipeline has never run. Treat it as **maximally idle** (infinite idle time) — it's automatically eligible and automatically wins over any pipeline that has ever actually run, all else equal. Don't error out or skip it.

## 3. Compute idle time and filter

`IDLE_NN = now - LAST_USED_NN` (or infinite, per the edge case above). Get `now` via `date -u +%s` (standalone Bash) and compare against the epoch form of `startTime` — don't hand-parse timestamps loosely; use a real date-diff (e.g. convert both to epoch seconds and subtract).

Keep only candidates where `IDLE_NN >= 1 day` (86400 seconds).

- **If the surviving set is empty** (every pipeline was used within the last day): **stop**. Report each pipeline's actual idle time to the operator and ask how they'd like to proceed (pick one anyway, wait, or pick a specific one). Do not silently fall back to "least-bad" — the whole point of the 1-day floor is to avoid stepping on an environment someone just used.

## 4. Pick the winner

Among survivors, pick the one with the **largest** `IDLE_NN` (the pipeline that's been idle the *longest* — i.e., the oldest last-usage timestamp). This is deliberately the opposite of "most recently used" — the goal is to grab the environment least likely to be in active use by someone else right now.

**Tie-break:** if two or more candidates have the exact same idle time (rare — e.g. both never-executed), pick the **lowest suffix number** deterministically. Don't ask the operator to break a tie that doesn't materially matter.

## 5. Derive the deploy argument

The winning pipeline's `-NN` suffix maps 1:1 to the deploy argument: `portal-react-boattrader-04` → `DEPLOY_ARG = "qa-04"`. This is a straight string transform — the `Source` stage's branch config for pipeline `-04` genuinely is `qa-04` (confirmed via `aws codepipeline get-pipeline --name portal-react-boattrader-04 --profile bg-qa`), not a heuristic.

## Worked example (real data, captured 2026-07-24)

| Pipeline | Last execution start | Idle |
|---|---|---|
| `-01` | 2026-07-16 | 8 days |
| `-02` | 2026-07-24 (same day) | <1 day — excluded |
| `-03` | 2026-07-17 | 7 days |
| `-04` | 2026-07-24 (same day, Failed) | <1 day — excluded |
| `-05` | 2026-07-06 | 18 days — **longest, wins** |
| `-06` | 2026-07-24 (same day) | <1 day — excluded |

Winner: `portal-react-boattrader-05` → `DEPLOY_ARG = "qa-05"`. Note a pipeline's most recent execution having `status: Failed` doesn't disqualify it from selection — "idle" is about *when* it last ran, not whether that run succeeded. (If the operator specifically wants to avoid re-using an environment that last failed, that's a judgment call to surface to them, not a hard rule — the user's stated rule is idle-time-based only.)
