<!-- MODULE_SUMMARY: Runtime validation gate for generated GitOps/ArgoCD manifests. Runs the deterministic render checks (kustomize build per overlay + ApplicationSet dir, helm template when the addon uses a Helm source) and then iac-eks-preflight (github.com/boatsgroup/iac-eks-preflight) as the PRIMARY, more-thorough k8s gate — it is version-aware (renders each chart at its pinned version), catches dead values keys, ApplicationSet↔config dereference gaps, AppProject permission errors, source render failures, object collisions, and sync-wave inversions that mobius-validate-service does not. Install-once/check-if-installed/install-if-missing model; a skipped check (exit 3) is never treated as a pass; an install or prerequisite failure reports the exact fix and does not silently skip. Called by add-service.md Phase 5 and update-service.md Phase 2 whenever an argocd/<addon>/ tree is generated or modified. -->

# GitOps Preflight Validation (shared)

Any `/mobius:*` command that **generates or modifies an `argocd/<addon>/` tree**
(base + `overlays/<env>/config.yaml`, ApplicationSet wiring, XIRSARole/XRD
claims, ClusterSecretStore, HTTPRoutes) MUST run this gate before it claims the
change is valid. It is the runtime counterpart to the static wiring checks: a
`kustomize build` that succeeds still ships a broken deploy if a values key the
chart no longer reads was set, an ApplicationSet dereferences a field the new
`config.yaml` doesn't provide, or the overlay names a nonexistent AppProject.

The primary gate is **`iac-eks-preflight`**
([`github.com/boatsgroup/iac-eks-preflight`](https://github.com/boatsgroup/iac-eks-preflight)),
which is deliberately **more thorough than `npx mobius-validate-service`** — it
resolves values against each chart's *pinned version*, renders sources exactly
as ArgoCD's repo-server does, and validates the whole ApplicationSet → config →
AppProject graph. `mobius-validate-service` stays as the convention check; it
does not replace this.

No cluster access is required — the tool is a purely static/offline analyzer of
the GitOps repos.

---

## Step G1 — Deterministic render checks (always)

These are the fast, dependency-free gates. Run them first; a failure here is a
`BLOCKER` and there's no point invoking preflight until they pass.

1. **`kustomize build` for each generated overlay** and for the relevant
   ApplicationSet directory in `<workspace_dir>/iac-eks-argocd`. (Already listed
   in add-service Phase 5 / update-service Phase 2 — this module is where those
   render checks now live so both commands share one definition.)
2. **`helm template` when the addon uses a Helm source** — render the pinned
   chart/version once and confirm it renders cleanly (reuse the cached render
   from `research-phase.md`'s Deep Inspection when it exists for this
   chart/version; do not re-render).
3. Confirm `argocd/<addon>/overlays/<env>/config.yaml` exists for every target
   env.

Terraform mode is out of scope for this module — its
`terraform fmt -check` / `terraform init -backend=false` / `terraform validate`
gate stays in add-service Phase 5 (it validates a `terraform/` tree, not an
`argocd/` tree).

---

## Step G2 — Ensure `iac-eks-preflight` is installed (install once)

`workspace_dir` here is the value the command **already resolved** via
[`shared/workspace-resolution.md`](workspace-resolution.md) (confirmed with the
user once, honors `MOBIUS_WORKSPACE`). Reuse it — do not re-derive the path from
`MOBIUS_WORKSPACE`/`$PWD`, or a user override that differs from both is ignored.

Always locate-or-clone the preflight repo into `workspace_dir` (G3 needs its
`install-helm-pin.sh` on every run, not just the install run), then install the
binary only if it's missing. The install script is idempotent, so re-running is
harmless — the `command -v` check just avoids doing work on a normal run.

```bash
# workspace_dir is already resolved by the command's Workspace Resolution gate.
PF_DIR="$workspace_dir/iac-eks-preflight"
# Private repo — the raw-URL curl one-liner needs auth, so clone the repo (same
# machinery as scripts/resolve-deps.sh) and use its bundled installer, which
# downloads a verified release binary via `gh release download` and falls back to
# `go build` from source when gh is unavailable. Do NOT use `go install ...@latest`
# — it fails on this private module ("terminal prompts disabled").
[ -d "$PF_DIR" ] || gh repo clone boatsgroup/iac-eks-preflight "$PF_DIR"
if ! command -v iac-eks-preflight >/dev/null 2>&1; then
  ( cd "$PF_DIR" && ./scripts/install.sh )   # installs to ~/.local/bin by default
fi
# install.sh drops the binary in ~/.local/bin, which is often not on PATH — add
# it, then re-verify. If it's still not found the install did not take.
export PATH="$HOME/.local/bin:$PATH"
command -v iac-eks-preflight >/dev/null 2>&1 || { echo "iac-eks-preflight still not on PATH after install"; exit 1; }
```

If the install fails (no `gh` auth **and** no Go toolchain, or `~/.local/bin`
not writable) — or the binary is still not on `PATH` after the re-check above —
the primary gate **cannot run at all**, which is a `BLOCKER`, not a warning.
**Stop and report the exact blocker and fix**; do not proceed to PR. Report e.g.
"iac-eks-preflight not installed and install failed: `gh` not authenticated and
`go` not on PATH — authenticate `gh` or install Go, then re-run Phase 5."
(`WARNING` is reserved for exit 3 in G5, where preflight *ran* but skipped an
individual check — a failed install means it never ran, so it can never be
downgraded to a warning.)

---

## Step G3 — Pin the helm/kustomize versions preflight renders with

`iac-eks-preflight` shells out to `helm` and `kustomize` the same way ArgoCD's
repo-server does, and it **cares which version** — a major-version mismatch
produces confident nonsense (running against the addons repo with Helm 4 emitted
1198 wave warnings vs 18 with the pinned pair). The cluster today
(ArgoCD v3.3.4 on ops-qa/ops-prod) uses **helm v3.19.4** and **kustomize
v5.8.1**; confirm those against the live cluster rather than trusting these
numbers indefinitely.

Install the version-pinned pair alongside the system binaries **and actually
point preflight at them** — setting only `GITOPS_EXPECT_*` without
`GITOPS_HELM`/`GITOPS_KUSTOMIZE` leaves preflight calling whatever system
helm/kustomize is on PATH, which is exactly the mismatch this step exists to
avoid. `install-helm-pin.sh` prints the `export` lines; capture them into the
current shell rather than running it in a throwaway subshell:

```bash
# NOT `( cd ... && install-helm-pin.sh )` — a subshell discards the exports it prints.
eval "$( cd "$PF_DIR" && ./scripts/install-helm-pin.sh )"   # installs pinned helm+kustomize, evals its GITOPS_HELM/GITOPS_KUSTOMIZE exports
export GITOPS_EXPECT_HELM=3.19.4
export GITOPS_EXPECT_KUSTOMIZE=5.8.1
# Confirm the pinned binaries are actually in effect (not the system ones):
[ -x "$GITOPS_HELM" ] && [ -x "$GITOPS_KUSTOMIZE" ] || { echo "pinned helm/kustomize not set — preflight would use system versions and mismatch"; exit 1; }
```

If `install-helm-pin.sh` doesn't export the paths in your environment, set
`GITOPS_HELM` / `GITOPS_KUSTOMIZE` explicitly to the pinned binaries it
installed. A check that reports **skipped** because of a version mismatch it
could not reconcile is exit code 3 (see G5) — treat it as unvalidated, not
passed.

---

## Step G4 — Run preflight against the generated tree

**Run G2–G5 in a single shell session.** G2 puts the binary on `PATH` and G3
exports `GITOPS_HELM` / `GITOPS_KUSTOMIZE` / `GITOPS_EXPECT_*` into the current
shell; those exports do **not** survive into a separate shell invocation. If this
gate is executed as one block, the run below inherits them. If you must run G4
(or `bump-chart` BC2's delta) in a fresh shell, **re-apply them first** —
`export PATH="$HOME/.local/bin:$PATH"` and re-`eval` the `install-helm-pin.sh`
exports (plus the `GITOPS_EXPECT_*` lines) — or preflight silently falls back to
system helm/kustomize and mismatches.

Run from the root of the repo/dir that holds the generated `argocd/<addon>/`
tree — with `--all`, preflight analyzes whatever directory it's invoked in, so
you **must** `cd` into that repo; running from the wrong cwd silently analyzes
the wrong tree and misses the new addon. `<gitops_tree_repo>` below is the
checkout the command generated `argocd/<addon>/` into (the service repo or the
addon config repo, whichever this command wrote to). Preflight also needs the
**control-plane repo `iac-eks-argocd`** (it derives every check from the
ApplicationSets there); point at it explicitly:

```bash
# cd into the repo holding the generated argocd/<addon>/ tree; workspace_dir is
# the command's already-resolved workspace (same one used in G2).
( cd "<gitops_tree_repo>" && iac-eks-preflight --all --control-plane "$workspace_dir/iac-eks-argocd" )
```

- Use **`--all`**, not the bare git-diff-scoped form: at Phase 5 the generated
  files may be un-/partially-committed, so git-diff scoping can miss them.
  `--all` checks the whole graph the new addon participates in.
- `--control-plane` may instead be supplied as `GITOPS_CONTROL_PLANE`, or omitted
  entirely if `iac-eks-argocd` is a sibling directory the tool can auto-find —
  but pass it explicitly here so the gate doesn't depend on layout luck.
- Add `--group-by claim` (or `addon`/`env`/`code`/`file`) to make findings
  readable when there are many.

**Chart-version bump (update-service bump-chart only — the `--all` render-gate
callers in add-service Phase 5 and update-service Phase 2 SKIP this subsection):**
run the version-aware delta
to see what the bump does to the values this addon already sets — it names keys
the new version drops (`KEY_DROPPED_BY_UPGRADE`) that a plain render cannot
surface:

```bash
# Same cwd rule as the --all run: delta reads the current pin and overlay values
# from the tree, so cd into the repo holding argocd/<addon>/ or it reads the wrong tree.
( cd "<gitops_tree_repo>" && iac-eks-preflight delta --addon <addon> --env <env> --to <new-version> )
```

**Ordering is load-bearing:** `delta --to <new>` compares the *currently pinned*
version in the tree against `<new>`. It must run **while the tree still holds the
old pin** — i.e. before `bump-chart` rewrites the version (Step BC2, before BC3
does the re-pin), not from the general Phase 2 gate that runs after BC3. If it
runs after the pin was already rewritten, "from" and "to" are both the new
version and no `KEY_DROPPED_BY_UPGRADE` finding can ever appear. Run it per
target env. A dropped key that the overlay still sets is a `BLOCKER`
(the value silently stops taking effect after the bump).

What it checks (categories `mobius-validate-service` does not cover): dead
values keys resolved against the chart's pinned version, missing `config.yaml`
fields an ApplicationSet dereferences (fails the *whole* ApplicationSet under
`missingkey=error`), AppProject permission errors (Application naming a
nonexistent project), configs no ApplicationSet reaches or naming the wrong
repo, sources that don't `kustomize build`/`helm template` cleanly, objects two
sources both emit (collisions), and sync-wave ordering inversions.

---

## Step G5 — Interpret exit codes (map to the change-safety severity model)

`iac-eks-preflight` exit codes map onto
[`shared/change-safety-validation.md`](change-safety-validation.md)'s severity
model:

| Exit | Meaning | Severity |
|------|---------|----------|
| `0` | clean | PASS |
| `1` | at least one **error** finding (won't self-converge; needs action) | `BLOCKER` |
| `2` | usage error / missing prerequisite / internal fault | `BLOCKER` — fix the invocation or prerequisite, then re-run |
| `3` | a check was **skipped** (e.g. version mismatch, offline cache miss) — **explicitly NOT a pass** | `WARNING` — surface it; the skipped surface is unvalidated |
| `4` | `--strict` and warnings present | `WARNING` (or `BLOCKER` if the command runs with `--strict`) |

Findings themselves split into **error** (won't heal on its own — a `BLOCKER`)
and **warning** (self-heals on ArgoCD/Crossplane retry, e.g. some wave
inversions — a `WARNING` to document). Never downgrade an `error` finding to a
warning to get past the gate.

**Hard rule:** exit `3` is never green. Report which checks were skipped and why,
and either fix the cause (usually a helm/kustomize version pin from G3) or record
the skipped surface as an explicit `WARNING` in the completion report. Do not
claim the manifests are validated when a check was skipped.

---

## Output contract

Return to the caller, for folding into the change-safety verdict:

- G1 render results (kustomize/helm) — pass/fail per overlay.
- Whether preflight was installed already or installed this run (and, if it could
  not be installed, the exact blocker + fix — this is itself a finding, not a
  silent skip).
- Preflight exit code and its severity mapping, plus the error/warning findings
  grouped as printed.
- Any skipped checks (exit 3) named explicitly, with cause.

`BLOCKER` count must be zero before the caller proceeds to PR creation.
