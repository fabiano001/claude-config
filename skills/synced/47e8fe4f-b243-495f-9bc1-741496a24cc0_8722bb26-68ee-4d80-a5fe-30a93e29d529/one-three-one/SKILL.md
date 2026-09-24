---
name: one-three-one
description: Use when making a business decision with multiple viable paths, writing a proposal or escalation for stakeholders, or when someone brings a problem without proposed solutions. Structures the decision as one problem, three distinct options with trade-offs, and one clear recommendation — for producing the analysis directly or coaching someone else through building their own.
---

# 1-3-1 Decision Making

## Overview

**1 Problem → 3 Options → 1 Recommendation.**

A structured format for decisions with real trade-offs. It forces clarity (one problem, stated plainly), prevents analysis paralysis (exactly three options, not ten), and kills lazy escalation (no bare problems without a recommendation attached).

## When to Use

- The user explicitly asks for "a 1-3-1" on something.
- A decision has multiple viable approaches with meaningful trade-offs (strategy, pricing, hiring, vendor selection, process change).
- The user needs a proposal or escalation to forward to a boss, stakeholder, or team.
- Someone (a report, a peer) brings a problem with no proposed solutions — use this to redirect them.

**Do NOT use for:** questions with one obvious answer, decisions the user has already made, or situations with no real trade-offs to weigh.

## The Format

| Section | Rule |
|---|---|
| **1. Problem** | One sentence. No "and" — if you need it, you have two problems. State the *what*, not the *how*. |
| **2. Options** | Exactly three, labeled A/B/C. Each gets a short description, pros, and cons. Must be genuinely different strategies — not three flavors of the same idea. |
| **3. Recommendation** | Pick one. State it directly with reasoning tied to the stated priorities. No hedging ("either could work," "it depends"). |
| **4. Success Criteria** | Concrete, verifiable outcomes if the recommendation is adopted. Not vague aspirations. |
| **5. Next Steps** | Action items with an owner and a rough timeline. |

If the reader picks a different option than recommended, Success Criteria and Next Steps get revised to match — they're not independent of the choice.

## Two Modes

### Mode 1 — Produce the analysis directly

Use when there's enough context to reason through the decision. Write the full 1-3-1 in one pass: Problem, three Options with pros/cons, Recommendation, Success Criteria, Next Steps.

### Mode 2 — Coach the user through building their own

Use when the user needs to send this to *their* stakeholder and should own the thinking. Go one question at a time:
1. "What's the one-sentence problem?" — push back if it contains "and."
2. "What are three genuinely different ways to solve this?" — push back on strawmen or near-duplicates.
3. "Which one do you actually recommend, and why?" — push back on hedging.
4. Draft Success Criteria and Next Steps together once the recommendation is settled.

## Delegation & Coaching

**When someone brings you a bare problem:** don't solve it for them. Redirect: *"Come back with three options and a recommendation."* This is the leadership use of 1-3-1 — it shifts ownership down instead of making you the bottleneck.

**Coaching someone through their first few:** watch for the same failure modes listed below (fake options, hedged picks, two problems in one). Point out the specific flaw rather than rewriting it for them — the goal is they can do this unassisted next time.

## Output & Saving

Default to a conversational response in the chat. If the user wants to share this with someone else (a memo, an escalation email, a doc for their team), offer to save it — and if saving, it **must** be written as a markdown file, e.g. `docs/decisions/YYYY-MM-DD-<topic>-1-3-1.md`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Two strawman options + the real pick | All three must be genuinely viable; if one is obviously worse, replace it with a real alternative. |
| Hedged recommendation | Pick one. "Recommendation: Option B" not "B or C could both work." |
| Two problems merged into one | Split the sentence. Run 1-3-1 on each separately, or narrow to the more urgent one. |
| Options that are minor variations | Each option should represent a distinct strategy, not the same approach with a different vendor/timeline. |
| Recommendation doesn't match stated priorities | If speed matters most, the pick can't be the slowest option without explaining why. |
| Vague success criteria | "Improve efficiency" → "Reduce turnaround from 5 days to 2 days." |

## Quick Reference

- [ ] Problem is one sentence, no "and"
- [ ] Exactly 3 options, each a distinct strategy, each with real pros/cons
- [ ] One recommendation, stated directly, no hedge
- [ ] Success criteria are specific and verifiable
- [ ] Next steps have an owner and a timeline

## Example

**Problem:** Our SaaS renewal rate has dropped 8 points this quarter and we need to decide how to respond before the board meeting.

**Options:**
- **A: Across-the-board price cut (10%).** Pros: Fast to implement, immediate signal to at-risk accounts. Cons: Cuts margin on accounts that weren't going to churn anyway; doesn't address root cause.
- **B: Dedicated retention team with proactive outreach.** Pros: Targets at-risk accounts specifically; builds a repeatable retention motion. Cons: 6-8 weeks to hire and ramp; no impact before the board meeting.
- **C: Bundle a new feature into existing plans at no extra cost.** Pros: Increases perceived value without cutting price; can ship in 2 weeks with the feature already in beta. Cons: Doesn't fix accounts churning for reasons unrelated to features (e.g., price, support).

**Recommendation:** Option C. It's fast enough to show the board a concrete action before the meeting, protects margin better than a blanket discount, and buys time to properly staff Option B afterward if churn doesn't improve.

**Success Criteria:**
- Feature bundled into all existing plans within 2 weeks.
- Renewal rate recovers at least 4 of the 8 lost points within one quarter.
- Churn-reason data collected from the next 20 cancellations to validate root cause.

**Next Steps:**
- Product to confirm feature is ready for GA — owner: Product lead, by end of week.
- CS to notify existing accounts of the bundle — owner: CS lead, within 3 days of GA.
- Revisit Option B staffing if renewal rate hasn't recovered by next quarter review — owner: VP Sales.
