---
name: save-session-info
description: Saves the CURRENT Claude Code session's info (session id, name, working directory, date) into ~/.claude/memory/sessions.md under a "# Saved Session: <Name>" heading — the same shared sessions.md file ticket-driver/ticket-creator/launch-resume-session already log into under per-ticket "# <TICKET-KEY>" headings, just a different heading scheme for a general-purpose, operator-named bookmark rather than a ticket-scoped worktree record. Before writing, checks whether this exact session id is already present under an existing "# Saved Session:" heading and skips (no duplicate entry) if so — it does not treat a session id appearing under an unrelated "# <TICKET-KEY>" entry as a conflict. The Name defaults to this session's own display name (looked up via `claude agents --all --json`, matched by session id — the same name shown in the background-agent view or set via `claude --name`/`--session-name`), or an explicit argument/operator-supplied name if that lookup comes up empty. Use when the operator asks to save/bookmark/remember this session, save session info, or runs /save-session-info. Do NOT use this for a ticket-driver/ticket-creator/research worktree session's own bookkeeping — those skills already log themselves into this same file under their own ticket headings; this skill is only for the operator bookmarking an arbitrary session, by name, for their own later reference.
---

# Save Session Info

Bookmarks the current Claude Code session into `~/.claude/memory/sessions.md` — the same file `ticket-driver`, `ticket-creator`, and `launch-resume-session` already write per-ticket entries into (under `# <TICKET-KEY>` headings) — so the operator can find this session again later by name. This skill adds a **different kind of entry** to that same file, under a `# Saved Session: <Name>` heading, for an arbitrary session the operator wants to bookmark (not necessarily tied to any ticket).

## Steps (in order — do not skip or reorder)

1. **Get the current session id.** Run `ls -t ~/.claude/projects/` (standalone Bash, no pipes) to find the most-recently-modified project subdirectory — that's this session's own project dir. Then run `ls -t ~/.claude/projects/<that-subdir>/` (standalone Bash); the first `.jsonl` filename listed (minus the `.jsonl` extension) is `SESSION_ID`, this session's UUID. This is the same lookup convention `ticket-creator`/`jira-sprint-manager` use for their own session logging — reuse it verbatim, don't invent a different method.

2. **Determine the Name.**
   - If the operator supplied one directly (e.g. as an argument to `/save-session-info`), use it verbatim as `NAME` and skip the lookup below.
   - Otherwise, run `claude agents --all --json` (standalone Bash) and find the entry whose `sessionId` field exactly equals `SESSION_ID`. If found and its `name` field is non-empty, `NAME` = that value — this is the session's real display name (whatever it's shown as in the background-agent view, or the current interactive tab's title if it was launched with `claude --name`).
   - If no matching entry is found, or the matching entry has no `name` field (e.g. a plain unnamed interactive session), ask the operator: **"What name would you like to save this session as?"** and use their reply as `NAME`. Do not guess or fabricate a name.

3. **Get the working directory.** Run `git rev-parse --show-toplevel` (standalone Bash). On success, use that full path as `SESSION_DIR`. On failure (not a git repo), run `pwd` and use that instead.

4. **Get the date.** Run `date +%Y-%m-%d` (standalone Bash) → `DATE`.

5. **Read `~/.claude/memory/sessions.md`** with the Read tool. If it doesn't exist yet, treat the existing content as empty (this first save will create the file) — though in practice it almost certainly already exists, since `ticket-driver`/`ticket-creator`/`launch-resume-session` log into it too.

6. **Check whether this session id is already saved as a bookmark — the required dedup check.** Scope this check to `# Saved Session: <Name>` headings ONLY — scan the file for that heading pattern, and within each such block, look for a line matching `- session id: <SESSION_ID>` (the same `SESSION_ID` from step 1). **Do not match a `session id:` line sitting under a `# <TICKET-KEY>` heading** — those belong to `ticket-driver`/`ticket-creator`/`launch-resume-session`'s own unrelated bookkeeping (e.g. `## ticket-driver` subentries) and are not a "this session is already bookmarked" signal, even if the id happens to match (the same session could legitimately be both mid-flight on a ticket AND separately bookmarked by name).
   - **Found under a `# Saved Session:` heading** → this session is already bookmarked. Print: `"Session <SESSION_ID> is already saved (as '<name from that heading>') — no changes made."` and **stop here** — do not write anything.
   - **Not found under any `# Saved Session:` heading** → proceed to step 7, even if the id appears elsewhere in the file under a ticket heading.

7. **Insert the new entry at the very top of the file** (newest-first, same ordering convention every other entry type in this file already uses), in exactly this shape:

   ```markdown
   # Saved Session: <NAME>

   - session id: <SESSION_ID>
   - directory: <SESSION_DIR>
   - date: <DATE>

   ```

   Prefix this block before whatever content the file already had (if any) — do not disturb or reorder any existing `# <TICKET-KEY>` entries. If the file didn't exist, this block becomes the entire file content.

8. **Write the updated file using the Write tool.** **NEVER** use shell redirection (`>`, `>>`) or `echo` to write it — this violates the repo's Bash safety rules and risks corrupting other skills' existing entries in this shared file.

9. **Confirm to the operator:** `"Saved session '<NAME>' (<SESSION_ID>) to ~/.claude/memory/sessions.md."`

## Notes

- This skill only ever acts on **this session** — it never saves or looks up any other session's info. To bookmark a different session, run this skill from within that session itself.
- This file is shared with other skills' own bookkeeping (`ticket-driver`, `ticket-creator`, `launch-resume-session`) — never delete, rewrite, or reorder any `# <TICKET-KEY>` entry while inserting a `# Saved Session:` entry.
- No automatic cleanup or expiry — saved entries accumulate until the operator manually edits the file.
- Duplicate **names** are allowed (two different sessions could legitimately share a display name) — only the session id is checked for duplication, per the operator's own instruction that this is the dedup key, and only among `# Saved Session:` entries.
