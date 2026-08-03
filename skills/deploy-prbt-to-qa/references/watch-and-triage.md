# Watch and triage (Steps 3–4 detail)

## Step 3a — Detect the new execution

Capture `BASELINE_EXECUTION_ID` = the execution id seen during Step 1's selection for the chosen pipeline (or `none` if it had zero executions). After running `boattrader-deploy-qa`, poll:

```bash
aws codepipeline list-pipeline-executions \
  --pipeline-name "portal-react-boattrader-NN" \
  --profile bg-qa --region us-east-1 \
  --max-items 1 --output json
```

every ~20-30 seconds. A new execution has registered when `pipelineExecutionSummaries[0].pipelineExecutionId` differs from `BASELINE_EXECUTION_ID`. **Timeout after ~5 minutes** of no new execution appearing — report this as a trigger failure (the `git push` may not have reached GitHub, the webhook may not have fired, or the branch move may have failed silently) rather than waiting indefinitely. Use `ScheduleWakeup` to pace this polling rather than a blocking sleep loop.

## Step 3b — Watch until terminal

```bash
aws codepipeline get-pipeline-state \
  --name "portal-react-boattrader-NN" \
  --profile bg-qa --region us-east-1 --output json
```

This returns `stageStates[]`, one entry per stage (`Source`, `BuildAndDeploy`, `E2ETesting`), each with `latestExecution.status`. Also cross-check the overall execution status via:

```bash
aws codepipeline get-pipeline-execution \
  --pipeline-name "portal-react-boattrader-NN" \
  --pipeline-execution-id "<the new execution id from Step 3a>" \
  --profile bg-qa --region us-east-1 --output json
```

`pipelineExecution.status` is the authoritative overall state. Poll both every ~60-120 seconds (`ScheduleWakeup`/`Monitor`, not an ad hoc loop) until it reaches a terminal value: `Succeeded`, `Failed`, `Stopped`, or `Superseded`.

**`Superseded`:** if a newer execution started (e.g. someone else pushed to the same `qa-NN` branch mid-watch), the one you're tracking gets superseded rather than finishing. Treat this as inconclusive, not a failure or a pass — report it plainly and stop; don't redeploy over someone else's concurrent use of the same environment.

## Step 3c — Identify which stage failed

When overall status is `Failed`, find the failing stage/action:

```bash
aws codepipeline get-pipeline-state --name "portal-react-boattrader-NN" --profile bg-qa \
  --query "stageStates[].{stage:stageName, status:latestExecution.status, actions:actionStates[].{name:actionName, status:latestExecution.status, buildId:latestExecution.externalExecutionId}}"
```

Exactly one of `BuildAndDeploy` or `E2ETesting` will show `status: Failed` (Source failing is rare — a bad branch push — treat it the same as a `BuildAndDeploy` failure if it happens: always real, no "unrelated" exception). Capture that action's `buildId` (`latestExecution.externalExecutionId`) — it's the CodeBuild build id you need next.

## Step 4a — Fetch the failing build's detail

```bash
aws codebuild batch-get-builds --ids "<buildId>" --profile bg-qa --region us-east-1 --output json
```

This gives `logs.groupName` / `logs.streamName` (CloudWatch Logs location) and `phases[]` (which build phase failed). Pull the actual log content:

```bash
aws logs get-log-events \
  --log-group-name "<logs.groupName>" \
  --log-stream-name "<logs.streamName>" \
  --profile bg-qa --region us-east-1 --output json
```

(Or `aws logs filter-log-events` if you need to search across a run without knowing the exact stream.) Read enough of the tail to see the actual error / failing assertion — don't guess from the phase name alone.

## Step 4b — `BuildAndDeploy` failure (always real)

No judgment call here. Read the log output, find the actual cause (compile error, lint failure, failed unit test, infra/deploy step failure, etc.), fix it in the source code on the branch being deployed, commit, push (to the **feature branch**, not `qa-NN` — the next `boattrader-deploy-qa` call re-points `qa-NN` at the new commit), then go back to SKILL.md Step 2 on the **same already-selected** environment and re-watch.

## Step 4c — `E2ETesting` failure (the nuanced case)

The Cypress build's log output names the failing spec/test. Read it, then judge:

**Treat as unrelated (→ overall pass) when:**
- The failing test's subject area (the page/component/flow it exercises, judged from its spec file name and test description) is **not touched by this branch's actual diff** — check `git diff main...HEAD` (or the relevant base) in the portal-react-boattrader checkout to see what files/areas this branch actually changed, and compare.
- The failure is an infra/flake-shaped error unrelated to app behavior (timeout waiting on an external fixture, a flaky selector unrelated to anything changed, a known-flaky test if the team has a documented flaky-test list — check for one, don't assume).
- The same test would plausibly fail on `main` too (i.e., it's a pre-existing failure, not something this branch introduced) — if you can quickly check a very recent successful pipeline run's E2E results for the same test having also failed there, that's strong corroborating evidence.

**Treat as real (→ same investigate/fix/redeploy loop as 4b) when:**
- The failing test's subject area overlaps with what this branch changed (e.g. the branch touches the SRP finance banner and the failing test is an SRP finance banner test) — this is very likely a real regression from the change.
- The failure message shows an actual assertion mismatch tied to app behavior your diff plausibly altered (wrong text, wrong element state, wrong navigation), not an infra/timeout shape.
- You can't find any evidence it's pre-existing/unrelated — when genuinely unsure, **default to treating it as real**. The cost of an unnecessary investigate-and-redeploy cycle is much lower than the cost of shipping a QA "pass" on a real regression.

**Either way, report the failing test by name and your reasoning** — don't just silently emit "pass" or "fail". If judged unrelated, the pass report must still mention "E2E test `<name>` failed but was judged unrelated to this change: `<one-line reasoning>`."

## Gotcha — SSO token expiry mid-watch

If any `aws` call during the watch loop starts failing with an auth error (typically mentions an expired token / `ExpiredTokenException` / a request for re-authentication), **stop polling and tell the operator to run `aws sso login --profile bg-qa`**, then resume watching once they confirm. Do not: (a) retry silently forever burning time on an unrecoverable error, or (b) report the deploy as "Failed" — an expired local credential is not a pipeline failure, and misreporting it as one would send the operator on a wrong-headed investigation.
