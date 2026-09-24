---
name: create-spike-document-tickets
description: After a spike has been researched and its Confluence spike-review document written (via create-spike-document), creates one real Jira ticket per follow-up work item the spike identified — each via its own forked /ticket-creator run so the fork inherits the spike's full research context instead of starting cold — sets every new ticket's Parent to the same parent story/epic the spike ticket itself has, and updates the Confluence page's existing "Jira Tickets" section with each one's key and link as it's created. Takes no required argument: the spike's Jira ticket key, the Confluence page URL, and the candidate ticket list are all resolved from the current session's own context (primarily the live Confluence page's own "Jira Tickets" section, which create-spike-document already seeded with brief descriptions) — if any of those three can't be determined confidently, it asks rather than guessing. Each forked ticket-creator run is explicitly instructed not to assume or guess any requirement, scope boundary, or design detail — if anything is unclear it must use the grill-me skill to ask the operator, or the research skill to verify against the codebase, before finishing; the resulting ticket must be complete enough for an executing agent to start implementation straight from it. Use when the operator asks to turn a completed spike's proposed tickets into real Jira tickets, spin up the follow-up tickets for a spike, or runs `/create-spike-document-tickets`. Do NOT use this to write or update the spike document's narrative content itself (that's create-spike-document) and do NOT use it to implement any ticket (that's ticket-driver) — this skill only creates the tickets and links them into the spike doc and their parent story.
---

# Create Spike Document Tickets

Turns a finished spike's proposed follow-up work into real, linked Jira tickets — one fork of the current session per ticket, each running `/ticket-creator` with the spike's own research already in its context, each held to a strict no-guessing bar. Every new ticket gets `Parent` set to the spike ticket's own parent, and the Confluence spike document gets updated with each ticket's key/link as soon as it's ready — not batched at the end.

## Non-negotiable rules (read before doing anything)

- **Never invent a ticket that wasn't actually discussed or listed.** The candidate list comes from what's already in this session or already written on the Confluence page — not from guessing what the spike "should" produce.
- **Never guess `SPIKE_KEY`, the Confluence URL, or `PARENT_KEY`.** If any can't be resolved confidently from context, ask the operator directly, once, before proceeding.
- **Every forked `/ticket-creator` run is told, explicitly, in its own prompt: no assumptions, no guesses — use `grill-me` or `research` instead.** This is not optional framing; include it verbatim in every fork's prompt (see Step 3).
- **Update the Confluence page per ticket, as each fork reports back — do not wait for all forks to finish.** A slow fork (e.g. stuck on a `grill-me` question) must not delay the tickets that already succeeded from showing up on the page.

## Fixed configuration

- **Cloud ID:** `ba2e3477-a4e5-4924-a530-47c471494d0f`

## Workflow

### Step 1 — Resolve `SPIKE_KEY`

The Jira ticket key of the spike this session just worked on. Look for it in the conversation's own context (the ticket you've been researching/writing up). If more than one plausible candidate exists, or none, ask the operator directly: **"Which spike ticket are these follow-up tickets for?"** Do not guess.

### Step 2 — Resolve `CONFLUENCE_URL`

The Confluence spike-document page this session already wrote or updated via `create-spike-document`. If it's not clearly established from context, ask: **"What's the Confluence page URL for this spike's document?"** Do not guess or search for one.

### Step 3 — Resolve `PARENT_KEY`

`mcp__atlassian__getJiraIssue` with `cloudId: ba2e3477-a4e5-4924-a530-47c471494d0f`, `issueIdOrKey: <SPIKE_KEY>`, `fields: ["parent"]`.

- **`fields.parent` present** → `PARENT_KEY = fields.parent.key`.
- **`fields.parent` absent/null** → stop. Tell the operator: `"<SPIKE_KEY> has no parent set — there's nothing to inherit. How do you want the new tickets' Parent field handled (leave unset, or give me a parent key)?"` Do not guess a parent, and do not silently leave it unset without asking first.

### Step 4 — Resolve `PROPOSED_TICKETS`

The list of follow-up work items the spike identified, each as a short title + brief description. Resolve in this order:

1. **Read the live Confluence page** (`mcp__atlassian__getConfluencePage` on `CONFLUENCE_URL`) and look at its current **"Jira Tickets"** section — `create-spike-document` already seeds this section with the set of tickets for the effort, each with a brief description, as part of writing the spike doc. Treat each entry there as one candidate ticket, using its existing brief description as the seed description for that ticket's own `/ticket-creator` run.
2. **If that section is empty, missing, or just placeholder text** (no real entries), fall back to whatever ticket list was already discussed/agreed in this session's own conversation.
3. **If neither source gives a clear, confident list**, ask the operator directly: **"What are the tickets to create for this spike?"** — do not invent items to fill a gap.

Confirm the resolved list back to the operator in one short line before proceeding (e.g. `"Creating 3 tickets: <title 1>, <title 2>, <title 3>."`) — cheap insurance against forking off the wrong set.

### Step 5 — Launch one fork per ticket (all in a single message, parallel)

For each entry in `PROPOSED_TICKETS`, call the `Agent` tool with `subagent_type: "fork"` (never a fresh/non-fork agent — the fork's inherited context is what lets `/ticket-creator` reuse this session's own spike research instead of re-researching from zero). Give each a short `description` and a distinct `name` (e.g. `ticket-creator-fork-<slug of the title>`).

**Prompt template for each fork** (fill in the bracketed parts; send verbatim otherwise — this wording is load-bearing, not paraphrase-safe):

```
/ticket-creator [<short title> — <the candidate's own brief description from Step 4, spelled out fully, not abbreviated>]

Non-negotiable rules for this run:
- Do not assume or guess any implementation detail, scope boundary, acceptance criterion, or design choice that hasn't actually been established — either already in this session's own context (the spike research, prior discussion), or by asking.
- If anything is unclear or unconfirmed while building this ticket, use the grill-me skill to ask the operator directly, or run the research skill against the codebase to verify — never proceed on a guess.
- The finished ticket must be a complete, self-contained account of what to build — detailed enough that an executing agent (e.g. /ticket-driver) could start implementation directly from it, with no further clarification needed.

Once /ticket-creator finishes and you have the new ticket's key:
1. Set its Parent field: mcp__atlassian__editJiraIssue, cloudId ba2e3477-a4e5-4924-a530-47c471494d0f, issueIdOrKey <the new key>, fields: {"parent": {"key": "<PARENT_KEY>"}}. [Omit this whole step if Step 3 resolved to "leave unset."]
2. Re-fetch the new ticket's `parent` field to confirm the write actually landed — don't just assume the edit call succeeding means the field is correct.
3. Report back plainly, as your final message: the new ticket's key, its full URL (https://boats-group.atlassian.net/browse/<KEY>), and whether the Parent field was confirmed set to <PARENT_KEY> (or explicitly note if it was left unset per instruction, or if the confirmation re-fetch didn't match).
```

### Step 6 — As each fork reports back, update the Confluence page immediately

Forks run in the background — each one's completion arrives as a task notification in a later turn, not inline in this one. Do not poll, and do not fabricate or predict a result before it actually arrives.

**As soon as any single fork reports back** (regardless of whether the others are still running):

- **Success** (ticket key + URL + Parent confirmed, or explicitly left unset per Step 3) → invoke the `create-spike-document` skill against `CONFLUENCE_URL`, as an update scoped to only its **"Jira Tickets"** section: replace that candidate's placeholder/draft line with the real `<KEY> — <short title>: <brief description>`, linked to the ticket's URL. `create-spike-document` re-reads the live page fresh on every call, so calling it once per completed fork (rather than batching) is safe and won't clobber a previous fork's just-added line.
- **Failure, or an ambiguous/incomplete report** (missing key/URL, Parent confirmation mismatch, or the fork reports it got stuck) → do NOT add anything to Confluence for that ticket, and do NOT guess a key or URL. Surface it to the operator plainly and ask how to proceed (retry that one ticket, fix the Parent field manually, or leave it out of the Confluence update) before moving on.

Repeat until every fork from Step 5 has reported back and been handled one way or the other.

### Step 7 — Final report

One line per ticket: key, URL, Parent-field outcome, and whether it made it into the Confluence page's Jira Tickets section. Call out any that failed or needed operator input along the way — don't bury a failure in an otherwise-successful-looking summary.

## Failure modes

- **`SPIKE_KEY` / `CONFLUENCE_URL` / `PROPOSED_TICKETS` can't be resolved confidently** → ask, per Steps 1/2/4. Never guess to keep moving.
- **`SPIKE_KEY` has no parent (Step 3)** → stop and ask how to handle it; don't silently proceed with an unset Parent unless the operator says to.
- **A fork's `/ticket-creator` run itself fails or gets stuck** → that's the fork's own problem to surface (it should report the failure plainly, per its own skill's failure handling); this skill's job is to not paper over it — see Step 6's failure branch.
- **The Parent-field edit succeeds but the confirmation re-fetch doesn't match** → the fork should report this explicitly rather than claiming success; treat it the same as a failure in Step 6 (ask before touching Confluence for that ticket).
- **`create-spike-document` update call fails for a given ticket** → report the verbatim error, keep going with the remaining forks' updates — one page-update failure doesn't block the others.
