---
name: deploy-prbt-to-qa
description: Deploys the current portal-react-boattrader branch to a QA environment end-to-end — picks the longest-idle portal-react-boattrader-NN AWS CodePipeline (idle >= 1 day, never the bare portal-react-boattrader pipeline), runs the boattrader-deploy-qa bash function to trigger it, watches the pipeline through Source/BuildAndDeploy/E2ETesting via AWS CLI (profile bg-qa), and on failure investigates, fixes, and redeploys — except an E2E failure judged unrelated to the change, which counts as a pass. Use when the user asks to deploy portal-react-boattrader (or "PRBT"/"boattrader portal") to QA, pick a QA environment and deploy, or run boattrader-deploy-qa. Do NOT use for deploying any other repo, for prod/stage deploys, or when the user just wants to check pipeline status without triggering a new deploy.
---

# Deploy portal-react-boattrader to QA

## Non-negotiable facts (verified against the real bash profile and AWS account — do not re-derive or second-guess these)

- **Function name:** `boattrader-deploy-qa` (defined in `~/.bash_profile`). **Argument format is `qa-NN`, NOT `bt-NN`** — e.g. `boattrader-deploy-qa qa-04`. It reads the CURRENT branch of wherever it's invoked from and deploys that.
- **AWS profile:** every `aws` CLI call in this skill MUST pass `--profile bg-qa`. The default profile is a *different* AWS account with zero boattrader resources — using it silently finds nothing. Region is `us-east-1` (bg-qa's default).
- **Resource type:** `aws codepipeline`, not `aws codebuild` directly. Real pipeline names: `portal-react-boattrader-01` through `-06` (exactly six exist today — do not assume `-07`/`-08` exist just because the bash function's regex allows `qa-07`/`qa-08`). **Never select the bare `portal-react-boattrader` pipeline** — always one with a `-NN` suffix.
- **Pipeline suffix ↔ deploy arg mapping is 1:1:** pipeline `portal-react-boattrader-04` watches Git branch `qa-04` — so the winning pipeline's `-NN` directly becomes `boattrader-deploy-qa qa-NN`.
- **Each pipeline has exactly 3 stages:** `Source` → `BuildAndDeploy` (CodeBuild project `portal-react-boattrader-NN-deploy`) → `E2ETesting` (CodeBuild project `portal-react-boattrader-NN-boattrader-cypress`, action `cypress-tests-boattrader`). **`E2ETesting` is "the E2E phase"** referenced in the triage rule below.

## Workflow

### Step 1 — Select the target QA environment

Pick the `portal-react-boattrader-NN` pipeline that's been idle the LONGEST, among those idle at least 1 day. Never the bare pipeline. If nothing qualifies (everything used within the last day), **stop and ask the operator** how to proceed — do not force a pick.

**Full algorithm, exact `aws` commands, and edge cases (zero-execution pipelines, tie-breaking) — load [references/pipeline-selection.md](references/pipeline-selection.md).**

Output of this step: `SELECTED_NN` (e.g. `04`) and `DEPLOY_ARG = "qa-04"`.

### Step 2 — Trigger the deploy

1. **Verify you're in the right place** — confirm the current working directory is inside a `portal-react-boattrader` git checkout: `git remote get-url origin` must contain `portal-react-boattrader`, and `git rev-parse --show-toplevel` must succeed. **If not, STOP and ask the operator to run this from inside the correct worktree** — do not guess a path or `cd` there yourself; this is what determines which branch actually gets deployed.
2. **Report before acting:** state the branch about to be deployed (`git rev-parse --abbrev-ref HEAD`) and the target environment (`DEPLOY_ARG`) — since this combination is exactly what determines what ships.
3. **Run it** (one Bash call, sourcing fresh since shell functions don't persist across separate tool calls):
   ```bash
   source ~/.bash_profile && boattrader-deploy-qa qa-<NN>
   ```
4. The function's `git push` to `qa-<NN>` happens **in the background** (`& disown` inside `deployBTPortal.sh`) — the Bash call returning does NOT mean the pipeline has started. Proceed to Step 3 to detect it.

### Step 3 — Detect and watch the new pipeline execution

Poll `list-pipeline-executions` for `portal-react-boattrader-<NN>` until a new execution appears (different `pipelineExecutionId` / newer `startTime` than Step 1's baseline) — timeout after a few minutes and report a trigger failure if nothing shows up. Then watch `get-pipeline-state` until the execution reaches a terminal status (`Succeeded` / `Failed` / `Stopped` / `Superseded`), polling periodically via this environment's `ScheduleWakeup`/`Monitor` tools rather than an ad hoc sleep loop.

**Full commands, polling cadence, and terminal-state / per-stage failure detection — load [references/watch-and-triage.md](references/watch-and-triage.md).**

### Step 4 — Triage the result

- **Succeeded** → done. Report pass, including the environment used and the branch deployed.
- **`BuildAndDeploy` failed** → always a real failure (no exception here). Investigate the CodeBuild logs, fix the actual problem on the source branch, commit + push the fix, then **go back to Step 2 on the SAME already-selected environment** (do not re-run Step 1's selection mid-cycle) and repeat Step 3.
- **`E2ETesting` failed** → the one nuanced case. Fetch the Cypress build's failure output and judge whether the failing test is actually related to what this branch changed, or a pre-existing/flaky/unrelated test.
  - **Judged unrelated** → treat the WHOLE pipeline run as a **pass** — but still report the unrelated E2E failure for visibility. Do not redeploy over it.
  - **Judged related/real** → same investigate → fix → commit/push → redeploy (Step 2, same environment) → re-watch (Step 3) loop as a `BuildAndDeploy` failure.

**Full judgment criteria for "unrelated" and the investigate/fix/redeploy loop — load [references/watch-and-triage.md](references/watch-and-triage.md).**

## Gotchas

- **SSO token expiry mid-watch:** if `aws` calls start failing with an auth/token-expired error partway through watching, tell the operator to run `aws sso login --profile bg-qa` — do not retry silently forever, and do not report a pipeline failure that was actually just an expired local credential.
- **Blast radius:** this skill only ever pushes to a `qa-0N` branch (never `main`) and only ever commits a genuine fix to the feature branch being deployed — it never touches another ticket's branch or another qa environment mid-run.

## Failure & fallback

- No `portal-react-boattrader-NN` pipeline idle ≥ 1 day → stop, list what you found (each pipeline + its idle time), ask the operator how to proceed.
- Not inside a `portal-react-boattrader` checkout → stop, ask the operator to `cd` into the correct worktree first.
- New pipeline execution never registers after triggering → stop, report the trigger appears to have failed (include the last known execution id/timestamp so the operator can check manually).
- Any `aws` call errors for a reason other than SSO expiry → stop and report the verbatim error; do not guess pipeline state from partial data.

## Output format

A short status report: environment selected + why (idle time), branch deployed, final pipeline status per stage, and — on a fix/redeploy cycle — what was wrong and what was changed. If an E2E failure was judged unrelated, say so explicitly rather than reporting a silent pass.
