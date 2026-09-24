# Universal Change Safety Validation

Shared module for validating generated or modified changes before and after PR
creation. Any `/mobius:*` command that writes files SHOULD call this module.

Goal: catch breakage and high-risk regressions early, then verify post-PR
feedback is handled before claiming completion.

---

## When to Run

Run this module after command-specific generation/validation and before final
completion.

- **Pre-PR gate**: required for any command that modifies files.
- **Post-PR scan**: required when the command creates PRs.

Skip only for read-only diagnostic/analysis commands that do not change files.

---

## Caller Input Contract

The calling command must provide:

1. `affected_repos`: exact repo paths modified in this run.
2. `changed_files_by_repo`: file lists from git diff.
3. `validation_commands_by_repo`: repo-native checks already known for that repo
   (lint/build/tests/validators).
4. `risk_profile`: one of `application-code`, `infrastructure-config`, `mixed`.
5. `rollback_strategy`: how to disable/revert safely.
6. `pr_targets` (if PRs are created): owner/repo/branch per PR.

Do not invent commands that do not exist in the target repo.

### Deriving Caller Input (Deterministic)

If the command did not precompute inputs, derive them in this order:

1. `affected_repos`: from command scope (single-repo or multi-repo phase plan).
2. `changed_files_by_repo`: `git -C <repo> diff --name-only` (working tree) and
   `git -C <repo> diff --cached --name-only` (staged).
3. `validation_commands_by_repo`: repo-native commands discovered from
   `package.json` scripts, Makefile targets, repo docs, or existing command spec.
4. `rollback_strategy`: command-provided rollback guidance; if missing, default to
   git-native revert/reset and document limitations.
5. `pr_targets`: infer from `gh pr create` parameters used by the command.

Record derived values in the validation report before running gates.

---

## Severity Model

Every finding must be classified as:

- `BLOCKER`: likely outage, broken deploy, data loss, security risk, or failed
  required check. Must be fixed before proceeding.
- `WARNING`: elevated risk but non-blocking for this run. Must be documented in
  completion report.
- `INFO`: non-actionable context.

Hard rule: if any `BLOCKER` remains, stop and fix before moving forward.

---

## Phase A - Pre-PR Validation Gate

Run this phase per repo in `affected_repos`, not globally.

### A0) Validation Surface Selection (Working Tree vs Staged)

Use this rule to avoid ambiguity:

- If command has already staged files, run A1-A7 against **staged diff**.
- If command has not staged yet, run A1-A7 against **working-tree diff**, then
  re-run A1 immediately after staging to confirm shipping surface.

Validation report must state which surface was used.

### A1) Workspace and Diff Integrity

- Confirm branch and clean staging intent (`git status --short`).
- Confirm only intended files are included in staged diff.
- Confirm no secrets/credentials files are accidentally staged.

Fail as `BLOCKER` if unintended high-risk files are staged.

### A2) Deterministic Static Checks

Run the strongest available local checks for each affected repo:

- Syntax/parse validity (language-native).
- Formatter/lint checks.
- Type checks (if typed language).
- Schema/manifest validation for infra repos.

Examples by repo style:

- Node app: `eslint`, `tsc --noEmit`.
- K8s/GitOps repo: `kustomize build` for modified overlays.
- Crossplane/KCL: render/validate commands used by that repo.

Any failed required deterministic check is a `BLOCKER`.

### A3) Build and Test Checks

- Run repo-native build command(s) where applicable.
- Run targeted tests related to changed files.
- Run command-specific validators (intake/wiring/graph/service) when relevant.

If tests are flaky or pre-existing failures exist, classify clearly:

- New failure caused by this run -> `BLOCKER`
- Known pre-existing unrelated failure -> `WARNING` with evidence

### A4) Risk Review of the Diff

Review changed hunks for behavior regressions that tools may miss:

- Error handling semantics preserved (status codes/messages/exit behavior).
- Startup and shutdown lifecycle safety preserved.
- Idempotency preserved on re-run.
- Import/order/bootstrap sequencing remains valid.
- Backward compatibility with existing config contracts.

This review is mandatory even when tests pass.

### A4.5) Instruction-Surface Hostile Review (commands/skills changes)

If `changed_files_by_repo` for the `mobius-tools` repo includes any
`commands/mobius/**`, `.claude/skills/**`, `docs/workflows/**` schema, or
`src/**` validator whose contract a command depends on, run the adversarial
review before the verdict:

> **Skill**: Read [`.claude/skills/command-change-hostile-review/SKILL.md`](../../../.claude/skills/command-change-hostile-review/SKILL.md)
> and review the final diff against every failure class it lists.

These specs drive live GitOps/Terraform/IAM changes, so a bad instruction is a
production-outage risk, not a failed test. Its `BLOCKER` findings gate the
Pre-PR verdict exactly like any other blocker. This is a separate review pass —
do not self-approve the spec you just wrote.

### A5) Security and Dependency Hygiene

At minimum:

- Secret leak scan on current validation surface.
- Dependency risk scan if dependency manifests/lockfiles changed.
- High-risk permission expansion review (IAM/RBAC/network exposure).

Tool selection policy:

- Prefer repo-native scanners from `validation_commands_by_repo`.
- If none exist, perform deterministic fallback checks:
  - grep-based secret pattern scan over changed hunks,
  - dependency manifest diff review with explicit risk notes.

Never claim a scanner passed if that scanner was not actually run.

Treat critical security findings as `BLOCKER`.

### A6) Rollback Readiness

Ensure rollback path is explicit, tested, and fast:

- Immediate disable path (feature flag/env toggle) if available.
- Git-native revert/reset path.
- Clear operator steps for rollback verification.

If no realistic rollback path exists, mark `BLOCKER` for high-risk changes,
otherwise `WARNING`.

### A7) Pre-PR Verdict

Emit a concise verdict table:

```text
Change Safety Verdict:
  Repo: <name>
  Deterministic checks: PASS/FAIL
  Build/tests: PASS/FAIL
  Diff risk review: PASS/FAIL
  Security/dependency: PASS/FAIL
  Rollback readiness: PASS/FAIL
  Blockers: <N>
  Warnings: <N>
```

Do not create PRs until `Blockers: 0`.

---

## Phase B - Post-PR Feedback Scan (if PRs created)

After PR creation, normalize feedback from all channels.

### B1) Collect Channels

For each PR:

```bash
gh pr checks <PR_NUMBER> --json name,bucket,state,conclusion,link
gh api repos/<owner>/<repo>/pulls/<PR_NUMBER>/reviews
gh api repos/<owner>/<repo>/pulls/<PR_NUMBER>/comments
gh api repos/<owner>/<repo>/issues/<PR_NUMBER>/comments
```

Channel meanings:

- `checks`: CI/security/status checks
- `reviews`: formal review states (`CHANGES_REQUESTED`, `APPROVED`, `COMMENTED`)
- `pulls/<PR>/comments`: inline code comments
- `issues/<PR>/comments`: conversation comments

### B2) Blocking Rules

Treat as `BLOCKER`:

- Any failing required check
- Any `CHANGES_REQUESTED` review
- Any high-severity security finding requiring code/config change

Required-check policy:

- If branch protection/required checks can be queried, use that set.
- If not available, treat failed checks as blockers and `skipping/neutral` as
  non-blocking unless command policy says otherwise.

Pending-check policy:

- `pending/in_progress` checks block final completion claim.
- Wait with bounded polling budget (default 10 minutes, configurable by command).
- On timeout, report as `WARNING` and state completion is provisional pending CI.

Treat as `WARNING`:

- Non-blocking bot suggestions
- Style nits without correctness/safety impact

### B3) Loop Behavior

If blockers exist:

1. Fix locally.
2. Re-run Phase A checks.
3. Push updates.
4. Re-run Phase B scan.

Repeat until blockers are zero or user explicitly pauses.

---

## Completion Contract

A command may claim completion only when all are true:

1. Phase A passed with zero blockers.
2. PR(s) created successfully (if applicable).
3. Phase B scan completed (if applicable).
4. Latest scan reports zero blockers.
5. Remaining warnings are explicitly listed in final report.

### Evidence Requirement

Final report must include:

- Commands executed per repo
- Pass/fail results per gate
- Blocking findings resolved (or none)
- Any provisional conditions (e.g., pending CI at timeout)

---

## Integration Snippet for Command Specs

Use this call pattern in command specs:

```markdown
> **Module**: Read [`shared/change-safety-validation.md`](shared/change-safety-validation.md)
> and execute Phase A before PR creation and Phase B after PR creation.
>
> Context for this command:
> - affected_repos: <...>
> - risk_profile: <application-code|infrastructure-config|mixed>
> - validation_commands_by_repo: <repo-native commands>
> - rollback_strategy: <kill-switch + git revert/reset>
```

---

## Notes for Maintainers

- Keep this module generic and repo-agnostic.
- Command-specific invariants should stay in command modules; this module defines
  universal gates and stop conditions.
- Prefer additive improvements here, then adopt across command specs incrementally.
