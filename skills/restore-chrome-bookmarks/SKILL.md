---
name: restore-chrome-bookmarks
description: Restores Google Chrome bookmarks after they get unexpectedly wiped, truncated, or reset back to a much smaller set. Compares each Chrome profile's live `Bookmarks` file against Chrome's own automatic `Bookmarks.bak` backup, shows both bookmark counts plus any URLs that exist only in the live file (which would be lost by restoring), confirms Chrome is fully quit before touching anything, backs up the current file, then copies the backup over the live file. Checks all profiles under `~/Library/Application Support/Google/Chrome/` and asks which one to target if more than one looks affected. Use when the user says their Chrome bookmarks got overwritten, wiped, reset, disappeared, shrank, or lost — or asks to restore/recover/undo/fix Chrome bookmarks. NOT for Chrome history, passwords, saved cards, extensions, or other browsers (Firefox, Safari, Edge) — those don't use this file or backup mechanism.
---

# Restore Chrome Bookmarks

Recovers a Chrome profile's bookmarks from Chrome's own automatic backup file, after the live
bookmarks file has been overwritten with a smaller/empty set (a recurring failure mode — often
tied to a bad sync state).

## Critical rules (read first)

1. **Never write to `Bookmarks` while Chrome is running.** Chrome holds its bookmark tree in memory
   and flushes it to disk on almost any save (a new bookmark, closing a window, quitting). If Chrome
   is still running when you restore the file, it will silently overwrite your fix with whatever it
   still has in memory — the exact failure this skill exists to fix. Always confirm full quit
   (Cmd+Q, not just closed windows) via `AskUserQuestion` before copying anything, then verify with
   `pgrep -f "Google Chrome"` (exit code 1 = fully quit, exit code 0 = still running — do not
   proceed if it's still running).
2. **Never use pipes (`|`), output redirection (`>`, `>>`, `2>&1`), or command substitution
   (`$(...)`, `` `...` ``) in Bash calls** — per this user's global shell rules. Run each command
   standalone; don't chain `date` into a `cp` filename via substitution — run `date +%F` as its own
   call first, read its plain-text output, then paste that literal string into the next command.
3. **Always back up the current live file before overwriting it**, even though it's "the broken
   one" — it may contain bookmarks added after the backup was taken (see step 3). Copy it to
   `Bookmarks.before-restore-<YYYY-MM-DD>` in the same profile directory. Never delete it.
4. **Never auto-restore without the counts and an explicit go-ahead.** A backup having more
   bookmarks than the live file is *usually* evidence of an overwrite, but it's also exactly what
   you'd see if the user deliberately deleted a bunch of bookmarks on purpose. Always show both
   counts (and the live-only URLs from step 3) and get explicit confirmation before copying.

## Workflow

### 1. Discover profiles and compare counts

Chrome profile directories live directly under `~/Library/Application Support/Google/Chrome/`
(`Default`, `Profile 2`, `Profile 3`, ...). List them:

```bash
ls -d ~/"Library/Application Support/Google/Chrome/Default" ~/"Library/Application Support/Google/Chrome/Profile "*
```

(Tilde expansion, not command substitution — no `$()`/backticks involved. If it errors because
there are no `Profile N` dirs, that's expected and just means only `Default` exists.)

For each profile directory found, run the comparison script — it handles missing files gracefully
and never modifies anything:

```bash
python3 ~/.claude/skills/restore-chrome-bookmarks/scripts/compare_bookmarks.py "<profile_dir>"
```

It prints JSON: `live_count`, `bak_count`, and `live_only_urls` (bookmarks that exist only in the
live file — present in the current, possibly-broken state, absent from the backup). A profile is a
restore **candidate** when `bak_exists` is true and `bak_count` is meaningfully greater than
`live_count`.

### 2. Pick the target profile

- One candidate → propose it directly, with both counts, and ask the user to confirm.
- Multiple candidates → list all of them (profile name + live count + backup count) via
  `AskUserQuestion` and let the user pick one (handle them one at a time — steps 3-6 repeat per
  profile; Chrome only needs to be quit once for all of them).
- No candidates (backup missing, or backup ≤ live) → say so plainly. Don't restore. If the user
  insists something is still missing, check whether Chrome sync is involved (see step 7) rather than
  forcing a restore that won't fix anything.

### 3. Surface bookmarks that would be lost

`live_only_urls` from step 1's script output is the list of bookmarks that exist only in the current
(broken) file — added after the backup was taken, so a straight copy-over would lose them. Show this
list to the user now, before restoring, so they know what to expect and can re-add them by hand
afterward. Don't attempt to programmatically merge them into the backup's JSON — the bookmark tree
uses per-node `id`/`guid` values that aren't safe to splice by hand between two independently-grown
trees; a plain list for manual re-adding is far lower-risk than a hand-merged file.

### 4. Confirm Chrome is fully quit

Ask via `AskUserQuestion` how the user wants to proceed — quit Chrome themselves, have you quit it
for them (`osascript -e 'quit app "Google Chrome"'` — note this closes every open window/tab, so
default to asking them to do it rather than doing it unprompted), or proceed without quitting
(discourage this — call out that it risks the fix being clobbered again). If they're quitting it
themselves, ask a second time for confirmation once it's done — do not assume; verify:

```bash
pgrep -f "Google Chrome"
```

Exit code `1` (no output) means fully quit — proceed. Exit code `0` means it's still running
(commonly just background helper/renderer processes left over, or the user only closed windows) —
stop and ask them to fully quit (Cmd+Q) before continuing.

### 5. Back up the live file, then restore

Get today's date as its own call first (see rule 2), then, for the chosen profile directory:

```bash
cp "<profile_dir>/Bookmarks" "<profile_dir>/Bookmarks.before-restore-<YYYY-MM-DD>"
cp "<profile_dir>/Bookmarks.bak" "<profile_dir>/Bookmarks"
ls -la "<profile_dir>/Bookmarks" "<profile_dir>/Bookmarks.bak" "<profile_dir>/Bookmarks.before-restore-<YYYY-MM-DD>"
```

### 6. Report

State plainly: restored count vs. previous count, where the pre-restore safety copy was written,
and repeat the live-only URL list from step 3 so it's not lost in scrollback. Tell the user they can
reopen Chrome now.

### 7. Flag the recurrence risk

If the user mentions this has happened before ("again"), mention that Chrome Sync can be the
underlying cause: if the account is signed in and sync re-pulls an older/smaller cloud bookmark
state after this restore, the fix can get silently undone again shortly after reopening Chrome.
Suggest they check `chrome://sync-internals` or the account's bookmark sync setting if it recurs —
this skill only fixes the local file, not why it got overwritten in the first place.
