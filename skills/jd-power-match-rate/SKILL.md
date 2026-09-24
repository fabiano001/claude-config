---
name: jd-power-match-rate
description: Refreshes the "JD Power Match Rate" Artifact — a daily dashboard of how often BoatTrader LendAPI applications' boat/engine data (make, model, and JD Power ModelTrimID) matches the JD Power catalog. Queries the production BigQuery table trident-funding.jd_power_matching.daily_match_rate incrementally (only days at or after the last recorded sync point, re-checking that day in case the rollup revised it), merges the new counts into the artifact's embedded data array, and republishes to the SAME existing artifact URL (never creates a new one). Use when the user asks to "update the JD Power match rate", "refresh the match rate dashboard/artifact", "sync the JD Power dashboard", or "pull the latest match rate numbers". Do NOT use for ad-hoc one-off analytics questions about loan applications (use bq-analyst for that) or for anything outside the jd_power_matching dataset.
---

Refresh the JD Power boat/engine catalog match-rate dashboard with the latest production data, then republish the same Artifact in place.

## State file — read this first

Read `state.json` in this skill's directory:

```json
{
  "artifactUrl": "<the published artifact URL — pass this to Artifact's `url` param>",
  "lastTrackedDay": "<YYYY-MM-DD — the most recent day already present in the artifact's data array>",
  "lastRunAt": "<YYYY-MM-DD>"
}
```

`artifactUrl` and `lastTrackedDay` are load-bearing. Never guess them — always read from this file.

## Step 1 — Query BigQuery incrementally

`daily_match_rate` is a scheduled daily rollup of the underlying per-application `enrichment_events`
table — it only contains fully-closed days, so it normally lags "today" by about a day. Don't expect
a row for the current calendar date.

Run exactly one `bq query` call (standalone Bash call, no pipes, no `&&`, no command substitution):

```bash
bq query --project_id=trident-funding --use_legacy_sql=false --format=json "SELECT * FROM \`trident-funding.jd_power_matching.daily_match_rate\` WHERE environment = 'production' AND day >= DATE('<lastTrackedDay>') ORDER BY day DESC"
```

Substitute `<lastTrackedDay>` with the value from `state.json`. This intentionally re-fetches
`lastTrackedDay` itself (the rollup could in principle revise a day after first writing it) plus any
newer closed days — it is NOT `lastTrackedDay + 1 day`.

If the query returns only the same row already in the artifact with identical values, there is
nothing to update: report that to the user and stop without touching the artifact file or
`state.json`.

## Step 2 — Merge into the artifact's data array

Read `artifact/match-rate.html`. Find the `DAILY` array in the `<script>` block — it is ordered most-recent-first, one object per day, with six fields per day:

```javascript
{
  day: "YYYY-MM-DD",
  boat_make: { present: N, matched: N },
  boat_model: { present: N, matched: N },
  boat_trim_id: { present: N, matched: N },
  engine_make: { present: N, matched: N },
  engine_model: { present: N, matched: N },
  engine_trim_id: { present: N, matched: N }
}
```

Map BigQuery's `<field>_attempts` column to `present` and `<field>_matched_count` to `matched` for
each of the six fields (`boat_make`, `boat_model`, `boat_trim_id`, `engine_make`, `engine_model`,
`engine_trim_id`).

For each day returned by the query:
- If a day object with that `day` already exists in `DAILY`, replace its six field objects in place.
  **Preserve that object's `note` field if it already has one** — never delete an existing note just
  because the counts changed.
- If the day is new (not in `DAILY`), insert a new object for it. New days never get a `note` field
  unless you are told to add one.

After merging, `DAILY` must stay sorted most-recent-first (`day` descending) — insert new days at the
correct position, don't just prepend blindly if somehow more than one new day came back.

Update the `LAST_SYNCED` constant near the top of the same `<script>` block to the max `day` now
present in `DAILY` (NOT today's calendar date — `daily_match_rate` lags by design, so `LAST_SYNCED`
should reflect the latest *closed* day, matching what the KPI cards and "Latest day" label show).

Use the Edit tool for this — never regenerate the whole file from scratch, and never touch anything
outside the `DAILY` array and `LAST_SYNCED` (styles, markup, and the rendering functions below the
data are stable and must not change as part of a routine refresh).

## Step 3 — Republish

Call the Artifact tool:
- `file_path`: the absolute path to `artifact/match-rate.html` in this skill's directory
- `url`: the `artifactUrl` value from `state.json` (this is what makes it update the existing page instead of creating a new one — never omit it)
- `favicon`: `🧭` (must stay identical across redeploys)
- Leave `title`/`description` unset — the file's own `<title>` tag and the description set at first publish already carry over.

## Step 4 — Update state.json

Overwrite `state.json` with:
- `artifactUrl`: unchanged
- `lastTrackedDay`: the max `day` now present in `DAILY` (same value used for `LAST_SYNCED` above)
- `lastRunAt`: today's date (`date +%Y-%m-%d`) — this is allowed to be later than `lastTrackedDay`, since the rollup lags.

## Reporting back

Tell the user which day(s) were added or updated and, briefly, the latest day's per-field match
rates. Do not re-summarize the whole table — that's what the artifact is for. Link the artifact URL.

## Data quality note worth knowing

`environment = 'production'` scopes to real production traffic, but it does not exclude synthetic
QA/E2E test applications run manually against production (e.g. a `--live-qa` run) — those insert real
rows with real `environment: 'production'` values because they call the real production Cloud
Function. If a day's numbers look anomalous, check whether a manual production test happened that day
before assuming a data or matching regression; if confirmed, add a short `note` to that day's object
(see Step 2) rather than silently leaving it unexplained.

Trim ID counts (`boat_trim_id`, `engine_trim_id`) reflect whether a JD Power ModelTrimID was resolved
— this only happens on a full model match. For boats this is currently always identical to the model
match count; for engines the attempt count can differ slightly from the model attempt count. This is
expected, not a bug — don't "fix" a mismatch between model and trim-ID numbers without checking the
normalization code first.
