---
name: create-boatsgroup-repo
description: Creates a new skeleton (empty) GitHub repository under the boatsgroup organization by driving the GitHub web UI with a headed Playwright browser — the `gh repo create` / GraphQL API path is blocked for this account by org policy (verified 2026-08-13: "does not have the correct permissions to execute CreateRepository"), but the same account can create repos through the web form. Takes one required argument, the repo name; always creates it as the org's only actually-selectable visibility, Internal (Private is present in the UI but disabled — "Restricted by organization policy" — and Public isn't offered at all), so it does NOT take or honor a visibility argument. Opens github.com/organizations/boatsgroup/repositories/new in a persistent, headed browser session; if GitHub's enterprise SSO challenge appears (first run, or an expired/cleared profile), pauses and asks the operator to complete sign-in in the visible window before continuing — never attempts to fill credentials itself. Fills the repository name, leaves the org's required custom properties (bypass_default_branch_rules, data_classification) at their defaults, leaves template/README/.gitignore/license unset for a bare skeleton repo, creates it, and returns the resulting repo URL — the caller needs this URL to push the first commit (`git remote add origin <url>` then `git push -u origin main`). Use when the user or a calling agent asks to create a new GitHub repo in boatsgroup, scaffold/create a skeleton or empty repository, or needs a fresh repo URL to push initial code to. Does NOT support Private or Public visibility (org-restricted), does NOT support any org/account other than boatsgroup, and does NOT push code, add collaborators, or configure branch protection — the caller does that once it has the URL.
---

# Create boatsgroup repo

Creates one new, empty repository under the `boatsgroup` GitHub org and hands back its URL. This exists because `gh repo create boatsgroup/<name>` fails outright for this account — confirmed 2026-08-13:

```
GraphQL: fabiano-desouza_boats does not have the correct permissions to execute `CreateRepository` (createRepository)
```

The same account CAN create repos through the GitHub web UI, so this skill drives that form with `playwright-cli` in headed mode instead of calling the API.

## Fixed configuration (do NOT prompt for these)

- **Org:** `boatsgroup`
- **New-repo URL:** `https://github.com/organizations/boatsgroup/repositories/new`
- **Visibility:** always **Internal** — verified 2026-08-13 by opening the visibility dropdown on this exact form: it offers only `Internal` (default, selected) and `Private` (rendered but disabled, labeled "Restricted by organization policy" — clicking it does not change the selection). `Public` is not offered as an option at all. **Do not accept or act on a visibility argument from the caller** — if one is passed, ignore it and proceed with Internal; do not ask the operator to pick, since there is nothing to pick.
- **Browser session:** use a fixed, named, persistent `playwright-cli` session — `-s=boatsgroup-repo-creator` — so a successful sign-in on one run is reused by later runs instead of re-triggering SSO every time.

## Input

One required argument: **repo name** (e.g. `fabi-loan-retry-service`). If it's missing from the invocation, ask the operator for it before doing anything else — do not guess a name.

Validate it loosely before opening a browser: non-empty, no spaces. GitHub itself will reject an invalid name via the inline "is available" check in Step 3 below, so don't over-engineer client-side validation — let the form be the source of truth.

## Workflow

### Step 1 — Open the browser and navigate

```
playwright-cli -s=boatsgroup-repo-creator open https://github.com/organizations/boatsgroup/repositories/new --headed --persistent
```

`--persistent` gives this session a profile on disk tied to the session name, so a prior sign-in survives across separate invocations of this skill. `--headed` is mandatory — this flow depends on a human being able to see and complete SSO if it's challenged.

### Step 2 — Check for an SSO/sign-in redirect

Take a snapshot. Look at the resulting page URL and title:

- **URL contains `/sso` or title starts with "Sign in"** → the profile isn't authenticated (first run, or GitHub invalidated the session). Take a screenshot, send it to the operator, and say plainly: a browser window is open on their machine at the GitHub sign-in page; ask them to complete sign-in/SSO there, then tell you when they're done. **Stop and wait for their reply — do not poll the page in a loop.** Once they confirm, re-`goto` the new-repo URL and re-check.
- **URL is already `https://github.com/organizations/boatsgroup/repositories/new` with title "New repository"** → already authenticated, proceed directly.

### Step 3 — Fill the repository name

Snapshot to get the current ref for the "Repository name *" textbox (refs are not stable across runs — always re-snapshot rather than reusing refs from a prior session). Fill it with the requested name:

```
playwright-cli -s=boatsgroup-repo-creator fill <name-field-ref> "<repo-name>"
```

Snapshot again and check the inline availability text next to the field:

- **"`<repo-name>` is available."** → proceed.
- **Anything else (taken, invalid characters, etc.)** → stop here. Report the exact inline message to the operator and ask for a different name — never auto-append a suffix or guess a variant yourself.

### Step 4 — Continue past required custom properties

Click **"Continue: Configuration"**. This org enforces two required custom properties on every repo — `bypass_default_branch_rules` and `data_classification` — both of which default to a safe value (`Default (false)` and `Default (unclassified)` respectively, verified 2026-08-13). Leave both at their defaults; a skeleton repo needs neither overridden.

**If a future org policy adds a required property with no default** (the "Continue" button is blocked, or a property shows an unset/placeholder state instead of a `Default (...)` value), stop and ask the operator what value to set — do not guess at an org policy field.

### Step 5 — Leave Configuration at its defaults, then create

On the Configuration step, confirm (via snapshot) that:
- Visibility shows **Internal** already selected — do not open or touch this control (see "Fixed configuration" above).
- "Start with a template" = **No template**
- "Add README" = **Off**
- "Add .gitignore" = **No .gitignore**
- "Add license" = **No license**

These are the form's own defaults for a bare skeleton repo — no interaction needed unless one of them has drifted from these values, in which case reset it to the value listed above before continuing.

Click **"Create repository"**.

### Step 6 — Confirm success and extract the URL

Snapshot once more:

- **Page URL is now `https://github.com/boatsgroup/<repo-name>`** (no longer `/new`) → success. The repo URL **is** that page URL.
- **Still on `/new`** → the submission failed validation. Capture and report whatever error text is visible on the page — do not assume success and do not retry blindly.

### Step 7 — Clean up and report

Close the browser tab's work is done, but leave the session itself alive for reuse next time (do NOT `close` or `delete-data` the `boatsgroup-repo-creator` session — that would throw away the persisted sign-in and force SSO again on the next run).

Report back to the caller/operator:

```
Created https://github.com/boatsgroup/<repo-name> (Internal visibility).
To push the first commit:
  git remote add origin git@github.com:boatsgroup/<repo-name>.git
  git branch -M main
  git push -u origin main
```

## Failure modes

- **Name already taken or rejected** → stop at Step 3, report the exact inline message, ask the operator for a different name.
- **SSO challenge** → stop at Step 2, hand off to the operator in the visible headed window, wait for their confirmation — never attempt credentials programmatically.
- **Still on `/new` after clicking Create** → stop at Step 6, report the visible error verbatim, do not retry blindly.
- **A new required custom property has no default** → stop at Step 4, ask the operator for the value.
- **`gh repo create` starts working again** (org policy may change) → that would be simpler and more reliable than this browser-automation path; if it's ever worth re-checking, a plain `gh repo create boatsgroup/<name> --private` (or without a visibility flag) is the thing to retry — but do not silently switch this skill's own mechanism without the operator's say-so.
