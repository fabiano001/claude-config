#!/usr/bin/env bash
# open-claude-session — open a Claude Code session in a new tab of the user's
# preferred terminal (iTerm2 if installed; Terminal.app as fallback).
#
# Tab-reuse semantics (iTerm2 only):
#   Each new tab is tagged with the marker `jsm:<basename-of-directory>` as its
#   tab name. On subsequent invocations for the same directory, the script
#   searches every iTerm2 window/tab/session for that marker; if found, it
#   focuses the existing tab and does NOT spawn a new session. This prevents
#   the "2 sessions opened for the same ticket across multiple skill runs"
#   problem the operator observed previously.
#
#   Caveat: the marker is the tab NAME, which iTerm2 will preserve only as long
#   as the user doesn't manually rename the tab. If the operator renames the
#   tab, the script can no longer detect it and will open a new tab. That's
#   acceptable — the operator's manual rename is an explicit "I want to track
#   this differently" signal.
#
#   Second caveat (introduced with --session-name below): per Claude Code's own
#   docs, `claude --name <n>` sets a display name "shown in /resume and the
#   terminal title." If your iTerm2 profile allows the running program to set
#   the tab title via escape sequence, Claude's own title-set could overwrite
#   this script's `jsm:<dirbasename>` tab-name marker shortly after the tab is
#   created, which would silently break reuse detection on the NEXT invocation
#   for the same directory (symptom: a duplicate tab opens instead of focusing
#   the existing one — the exact bug the marker exists to prevent). This has
#   NOT been empirically verified either way. If you observe duplicate tabs
#   after adopting --session-name, the fix is either (a) in iTerm2 Preferences
#   → Profiles → Terminal, disable "Terminal may set the tab/window title" for
#   the profile these tabs use, or (b) stop passing --session-name.
#
# Tab-placement semantics (iTerm2 only):
#   When opening a NEW tab:
#     - If iTerm2 already has an open window, the new tab is created in that
#       window (alongside the operator's existing tabs).
#     - If iTerm2 has no open windows, a new window is created with the new tab.
#
# Terminal.app fallback (only when iTerm2 is NOT installed):
#   Opens a new Terminal.app window. No tab-reuse detection — the fallback is
#   intentionally minimal because the operator's primary terminal is iTerm2.
#   The "Terminal.app activate + do-script opens 2 windows" gotcha (when
#   Terminal.app wasn't already running) is mitigated by the `reopen` check.
#
# Session naming (--session-name):
#   Passes `claude --name "<value>"` at startup, which sets Claude Code's own
#   display name for the session — shown in the `/resume` picker, the agent
#   view (`/background`), the statusline `session_name` field, and (per
#   Claude's docs) the terminal title. This is the thing that otherwise
#   requires a manual Ctrl+R in the session picker to set after the fact.
#   Also works when PAIRED WITH --resume, not just on a fresh session —
#   empirically verified (2026-07-31, launch-resume-session): resuming a
#   session with --session-name set to something different from its original
#   name correctly overrides the display name shown in `claude agents --json`
#   going forward. (An earlier version of this comment claimed --session-name
#   only worked on fresh sessions and was silently ineffective on --resume —
#   that claim was never actually tested and turned out to be wrong; don't
#   reintroduce it without re-verifying first.)
#
# Model override (--model):
#   Passes `claude --model "<value>"` at startup, which pins the new session
#   to that model instead of whatever it would otherwise default to. Accepts
#   any value `claude --model` itself accepts (alias or full model name) —
#   this script does not validate or interpret it. Only meaningful when
#   starting a NEW session (paired with --prompt, not --resume) — same
#   restriction as --session-name, for the same reason.
#
# Auto-close on background (--auto-close-on-background, iTerm2 only):
#   Opt-in. Only meaningful when this call BOTH creates a brand-new tab (not
#   when an existing tab is reused/focused — that path is left alone) AND
#   the submitted --prompt starts with `/background`. When set, after typing
#   the command into the new tab, the script polls that SAME tab's on-screen
#   contents (by direct AppleScript object reference — NOT by the jsm: name
#   marker, which per the caveat above can get overwritten within seconds) once
#   per second, up to 20 seconds, for the literal substring `backgrounded ·`
#   — the exact text Claude Code itself prints the instant a `/background`
#   handoff completes. The moment it appears, the now-idle tab is closed
#   automatically. If it never appears within the timeout (slow startup, an
#   MCP auth prompt blocking, or the dispatched command erroring before it
#   could background), the tab is left open on purpose — closing a tab that
#   might be showing an error the operator needs to see would be worse than
#   the idle-tab annoyance this flag exists to fix.
#
#   Empirically verified (2026-07-30, PR #301 review launch): startup +
#   handoff took ~3 seconds end to end, well inside the 20s budget.
#
#   Not implemented for the Terminal.app fallback — that path has no
#   equivalent object-reference/marker mechanism to poll or close by.
#
# Usage:
#   open-claude-session.sh <directory> [--resume <session-id>] [--prompt <text>] [--session-name <name>] [--model <model>] [--auto-close-on-background]
#
# Examples:
#   open-claude-session.sh ~/Code/webapp-react-trident
#   open-claude-session.sh ~/Code/webapp-react-trident \
#     --resume 7bc44dd0-f06f-4bf4-8922-15e20cc11856
#   open-claude-session.sh ~/Code/webapp-react-trident-worktree-2 \
#     --prompt "/ticket-driver TRIDENT-904"
#   open-claude-session.sh ~/Code/webapp-react-trident-worktree-2 \
#     --resume b7b345eb-d138-446a-a30f-465b84c35043 \
#     --prompt "/review-pr-comments https://github.com/boatsgroup/webapp-react-trident/pull/243 autonomous"
#   open-claude-session.sh ~/Code/webapp-react-trident-TRIDENT-904 \
#     --prompt "/background /ticket-driver TRIDENT-904" \
#     --session-name "TRIDENT-904-WEBAPP"
#   open-claude-session.sh ~/.claude/pr-reviews/boatsgroup-webapp-react-trident-301 \
#     --prompt "/background /review-pr https://github.com/boatsgroup/webapp-react-trident/pull/301" \
#     --session-name "PR REVIEW - TRIDENT-974" \
#     --auto-close-on-background
#
# Exit codes:
#   0  success — tab opened or focused.
#   1  directory does not exist.
#   2  bad arguments.

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <directory> [--resume <session-id>] [--prompt <text>] [--session-name <name>] [--model <model>] [--auto-close-on-background]" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

DIR="$1"
shift

SESSION_ID=""
PROMPT=""
SESSION_NAME=""
AUTO_CLOSE=false
MODEL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto-close-on-background)
      AUTO_CLOSE=true
      shift
      ;;
    --model)
      if [ "$#" -lt 2 ]; then
        echo "Error: --model requires a value" >&2
        usage
        exit 2
      fi
      MODEL="$2"
      shift 2
      ;;
    --resume)
      if [ "$#" -lt 2 ]; then
        echo "Error: --resume requires a session-id value" >&2
        usage
        exit 2
      fi
      SESSION_ID="$2"
      shift 2
      ;;
    --prompt)
      if [ "$#" -lt 2 ]; then
        echo "Error: --prompt requires a value" >&2
        usage
        exit 2
      fi
      PROMPT="$2"
      shift 2
      ;;
    --session-name)
      if [ "$#" -lt 2 ]; then
        echo "Error: --session-name requires a value" >&2
        usage
        exit 2
      fi
      SESSION_NAME="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Expand a leading ~ to $HOME.
DIR_EXPANDED="${DIR/#\~/$HOME}"

if [ ! -d "$DIR_EXPANDED" ]; then
  echo "Error: directory does not exist: $DIR_EXPANDED" >&2
  exit 1
fi

# Resolve to absolute path.
DIR_ABS="$(cd "$DIR_EXPANDED" && pwd)"
DIR_BASENAME="$(basename "$DIR_ABS")"

# Build the claude invocation. See header comment for quoting rationale.
CLAUDE_INVOCATION="claude"

if [ -n "$SESSION_NAME" ]; then
  # Escape embedded double-quotes so the value can't break out of the
  # double-quoted argument below.
  SESSION_NAME_ESCAPED="${SESSION_NAME//\"/\\\"}"
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION --name \"$SESSION_NAME_ESCAPED\""
fi

if [ -n "$MODEL" ]; then
  MODEL_ESCAPED="${MODEL//\"/\\\"}"
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION --model \"$MODEL_ESCAPED\""
fi

if [ -n "$SESSION_ID" ]; then
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION --resume \"$SESSION_ID\""
fi

if [ -n "$PROMPT" ]; then
  # Route the prompt through a temp file instead of typing it inline. Why:
  # `write text` below simulates real keystrokes into the tab's TTY, which is
  # in canonical (line-buffered) mode — macOS caps that per-line buffer at
  # 1024 bytes (MAX_INPUT). A long prompt pushes the WHOLE typed command line
  # (cd ... && claude ... '<prompt>') past that limit, and everything past
  # the cutoff — including the trailing newline that submits the command —
  # gets silently dropped by the kernel. Symptom: the command just sits there
  # half-typed forever, nothing ever runs. (Empirically hit 2026-07-31 with a
  # multi-paragraph /launch-research-agent prompt; short prompts like ticket
  # keys or PR URLs stay well under 1024 bytes, which is why this wasn't
  # caught earlier.) Writing the prompt to a file keeps the TYPED command
  # short and fixed-length no matter how long the prompt itself is — the
  # remote shell reads (and deletes) the file itself, not the TTY line buffer.
  mkdir -p "$HOME/.claude/tmp/open-claude-session"
  PROMPT_TMPFILE="$(mktemp "$HOME/.claude/tmp/open-claude-session/prompt.XXXXXX")"
  printf '%s' "$PROMPT" >"$PROMPT_TMPFILE"
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION \"\$(cat '$PROMPT_TMPFILE'; rm -f '$PROMPT_TMPFILE')\""
fi

SHELL_CMD="cd \"$DIR_ABS\" && $CLAUDE_INVOCATION"

# Tab name marker used for iTerm2 reuse detection.
TAB_MARKER="jsm:$DIR_BASENAME"

# Detect iTerm2 by app bundle presence (not by process — we want to use it
# even if it's not currently running).
if [ -d "/Applications/iTerm.app" ] || [ -d "$HOME/Applications/iTerm.app" ]; then
  USE_ITERM=true
else
  USE_ITERM=false
fi

# AppleScript needs every embedded double-quote escaped as \".
APPLESCRIPT_CMD="${SHELL_CMD//\"/\\\"}"

# AppleScript boolean literal for the auto-close branch below.
if [ "$AUTO_CLOSE" = true ]; then
  AUTO_CLOSE_APPLESCRIPT="true"
else
  AUTO_CLOSE_APPLESCRIPT="false"
fi

if [ "$USE_ITERM" = true ]; then
  # iTerm2 path. The heredoc interpolates $TAB_MARKER, $APPLESCRIPT_CMD, and
  # $AUTO_CLOSE_APPLESCRIPT via bash before osascript sees the script. All are
  # safe: TAB_MARKER is alphanumeric + colon, APPLESCRIPT_CMD has been
  # pre-escaped for quotes, and AUTO_CLOSE_APPLESCRIPT is a fixed literal.
  REUSE_RESULT=$(osascript <<APPLESCRIPT
tell application "iTerm"
  -- Deliberately NOT calling "activate" here. Empirically confirmed
  -- (2026-08-03): tab creation + write text work correctly without it —
  -- "activate" does a real OS-level frontmost-app switch, and macOS
  -- delivers an in-flight keystroke to whichever window is frontmost AT
  -- DELIVERY TIME, not whichever was frontmost when the key was pressed.
  -- Reproduced for real: an operator mid-keystroke in their own terminal
  -- had a stray character land at the front of the injected "cd ... && claude"
  -- command the instant this script's old "activate" call flipped frontmost
  -- status, corrupting the command (e.g. "hcd <path> && claude ..."). Every
  -- one of this script's callers is explicitly designed so the operator's
  -- current session "stays free while it runs elsewhere" — never yanking
  -- focus also happens to match that intent, not just fix the race. Do not
  -- reintroduce "activate" without re-verifying this exact hazard first.

  -- Search every existing window/tab/session for our marker.
  set foundSession to missing value
  set foundWindow to missing value
  set foundTab to missing value
  try
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          try
            if name of s is "$TAB_MARKER" then
              set foundSession to s
              set foundWindow to w
              set foundTab to t
              exit repeat
            end if
          end try
        end repeat
        if foundSession is not missing value then exit repeat
      end repeat
      if foundSession is not missing value then exit repeat
    end repeat
  end try

  if foundSession is not missing value then
    -- Existing tab found — focus it; do NOT re-run the claude command (the
    -- ongoing session would get a stray /command if we did).
    tell foundWindow to select
    tell foundTab to select
    return "reused"
  else
    -- No existing tab — create a new one in the current window if there is
    -- one, otherwise spawn a new window.
    if (count of windows) is 0 then
      create window with default profile
    else
      tell current window to create tab with default profile
    end if
    -- The newly-created tab's session becomes the current session. Capture
    -- direct object references now — NOT by name — since the tab-name marker
    -- can get overwritten within seconds (see header comment), which would
    -- break a later name-based lookup for the auto-close poll below.
    set newSession to current session of current window
    set newTab to current tab of current window
    tell newSession
      set name to "$TAB_MARKER"
      write text "$APPLESCRIPT_CMD"
    end tell

    if $AUTO_CLOSE_APPLESCRIPT then
      -- Poll the SAME session object (immune to the name/title being
      -- overwritten) for Claude Code's own "backgrounded ·" completion
      -- line. Once seen, the tab is idle and safe to close. Bounded to
      -- ~20s; if it never appears, leave the tab open rather than risk
      -- closing one that's still starting up or showing an error.
      set didClose to false
      repeat with i from 1 to 20
        delay 1
        try
          if (contents of newSession) contains "backgrounded ·" then
            close newTab
            set didClose to true
            exit repeat
          end if
        end try
      end repeat
      if didClose then
        return "created-closed"
      else
        -- Diagnostics: don't just report an ambiguous timeout. Grab the
        -- last few non-empty lines of the tab's own contents so the caller
        -- can see whether this was a slow-but-healthy startup or an actual
        -- error (e.g. a corrupted command line, "command not found") —
        -- exactly the kind of thing that previously required manually
        -- cross-checking 'claude agents' and 'ps aux' to figure out.
        -- NOTE: never use backticks in ANY comment inside this heredoc —
        -- bash treats unquoted-heredoc backticks as real command
        -- substitution, not AppleScript comment text. This exact mistake
        -- (backticks around "claude agents" and "ps aux" in this very
        -- comment) actually executed both commands and spliced the second
        -- one's full output into the AppleScript source, breaking the parser.
        -- Empirically confirmed and fixed 2026-08-03. Use single-quotes for
        -- inline "code" styling in comments here instead, always.
        set tailSnippet to ""
        try
          set fullContents to (contents of newSession)
          set savedTIDs to AppleScript's text item delimiters
          set AppleScript's text item delimiters to {return, linefeed}
          set allLines to text items of fullContents
          set AppleScript's text item delimiters to savedTIDs
          -- Blank terminal rows come back padded with trailing spaces, NOT
          -- as literal empty strings — a plain 'is not ""' check (tried
          -- first, empirically found broken 2026-08-03) lets whitespace-only
          -- rows through as "non-empty", so the tail ends up being the
          -- blank rows below the real content instead of the real content
          -- itself. Checking for actual word content correctly excludes
          -- whitespace-only rows (a pure-whitespace string tokenizes to
          -- zero words) while still keeping any row with real text.
          set nonEmptyLines to {}
          repeat with ln in allLines
            if (count of words of (ln as string)) > 0 then
              set end of nonEmptyLines to (ln as string)
            end if
          end repeat
          set totalLines to count of nonEmptyLines
          set tailCount to 5
          if totalLines < tailCount then set tailCount to totalLines
          if tailCount > 0 then
            set tailLines to {}
            repeat with i from (totalLines - tailCount + 1) to totalLines
              set end of tailLines to (item i of nonEmptyLines)
            end repeat
            set AppleScript's text item delimiters to " | "
            set tailSnippet to (tailLines as string)
            set AppleScript's text item delimiters to savedTIDs
          end if
        end try
        -- Use "linefeed" (ASCII 10 / \n), NOT the "return" constant (ASCII
        -- 13 / \r) as the separator here — bash's own splitting logic below
        -- looks for $'\n' specifically. Mixing these up (empirically hit
        -- 2026-08-03) makes the split silently never match: REUSE_STATUS
        -- ends up as the whole "status\rtail" string glued together, which
        -- never equals the bare "created-close-timeout" bash compares
        -- against, so the timeout diagnostic message never prints at all.
        return "created-close-timeout" & linefeed & tailSnippet
      end if
    else
      return "created"
    end if
  end if
end tell
APPLESCRIPT
)

  NAME_SUFFIX=""
  if [ -n "$SESSION_NAME" ]; then
    NAME_SUFFIX=" (named '$SESSION_NAME')"
  fi

  # The timeout status is the only one that can carry a second line (a
  # diagnostic content tail) — split it off. For every other status this is
  # a no-op: a single-line value has no "$'\n'" in it, so REUSE_STATUS just
  # equals REUSE_RESULT unchanged and REUSE_DETAIL stays empty.
  REUSE_STATUS="${REUSE_RESULT%%$'\n'*}"
  REUSE_DETAIL=""
  if [ "$REUSE_STATUS" != "$REUSE_RESULT" ]; then
    REUSE_DETAIL="${REUSE_RESULT#*$'\n'}"
  fi

  if [ "$REUSE_STATUS" = "reused" ]; then
    echo "iTerm2: focused existing tab '$TAB_MARKER' in $DIR_ABS (no new Claude session opened)."
  else
    if [ -n "$SESSION_ID" ] && [ -n "$PROMPT" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — resuming Claude session $SESSION_ID with initial prompt: $PROMPT"
    elif [ -n "$SESSION_ID" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — resuming Claude session $SESSION_ID"
    elif [ -n "$PROMPT" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — fresh Claude session$NAME_SUFFIX with initial prompt: $PROMPT"
    else
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — fresh Claude session$NAME_SUFFIX"
    fi

    if [ "$REUSE_STATUS" = "created-closed" ]; then
      echo "iTerm2: /background handoff detected — the now-idle tab was closed automatically."
    elif [ "$REUSE_STATUS" = "created-close-timeout" ]; then
      echo "iTerm2: --auto-close-on-background was set but no /background handoff was detected within 20s — leaving the tab open."
      if [ -n "$REUSE_DETAIL" ]; then
        echo "iTerm2: tab's last output before giving up: $REUSE_DETAIL"
        echo "iTerm2: inspect that line yourself — a shell error there (e.g. \"command not found\") means the resume/launch itself failed, not just a slow startup."
      else
        echo "iTerm2: no readable output was captured from the tab to help diagnose why."
      fi
    fi
  fi
else
  NAME_SUFFIX=""
  if [ -n "$SESSION_NAME" ]; then
    NAME_SUFFIX=" (named '$SESSION_NAME')"
  fi

  # Terminal.app fallback. The `if not running` mitigation prevents the
  # "activate + do-script opens 2 windows" gotcha when Terminal wasn't
  # previously running.
  osascript \
    -e "tell application \"Terminal\"" \
    -e "  if not (exists window 1) then reopen" \
    -e "  activate" \
    -e "  do script \"$APPLESCRIPT_CMD\"" \
    -e "end tell" >/dev/null

  if [ -n "$SESSION_ID" ]; then
    echo "Terminal.app (iTerm2 not installed): opened new window in $DIR_ABS — resuming Claude session $SESSION_ID"
  else
    echo "Terminal.app (iTerm2 not installed): opened new window in $DIR_ABS — fresh Claude session$NAME_SUFFIX"
  fi
fi
