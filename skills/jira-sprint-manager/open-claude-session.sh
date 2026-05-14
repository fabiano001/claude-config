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
# Usage:
#   open-claude-session.sh <directory> [--resume <session-id>] [--prompt <text>]
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
#
# Exit codes:
#   0  success — tab opened or focused.
#   1  directory does not exist.
#   2  bad arguments.

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <directory> [--resume <session-id>] [--prompt <text>]" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

DIR="$1"
shift

SESSION_ID=""
PROMPT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
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

if [ -n "$SESSION_ID" ]; then
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION --resume \"$SESSION_ID\""
fi

if [ -n "$PROMPT" ]; then
  # Escape embedded single quotes via the bash `'\''` idiom so we can safely
  # wrap the prompt in single quotes (the shell will not interpolate inside).
  PROMPT_ESCAPED="${PROMPT//\'/\'\\\'\'}"
  CLAUDE_INVOCATION="$CLAUDE_INVOCATION '$PROMPT_ESCAPED'"
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

if [ "$USE_ITERM" = true ]; then
  # iTerm2 path. The heredoc interpolates $TAB_MARKER and $APPLESCRIPT_CMD via
  # bash before osascript sees the script. Both values are safe: TAB_MARKER is
  # alphanumeric + colon, and APPLESCRIPT_CMD has been pre-escaped for quotes.
  REUSE_RESULT=$(osascript <<APPLESCRIPT
tell application "iTerm"
  activate

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
    -- The newly-created tab's session becomes the current session.
    tell current session of current window
      set name to "$TAB_MARKER"
      write text "$APPLESCRIPT_CMD"
    end tell
    return "created"
  end if
end tell
APPLESCRIPT
)

  if [ "$REUSE_RESULT" = "reused" ]; then
    echo "iTerm2: focused existing tab '$TAB_MARKER' in $DIR_ABS (no new Claude session opened)."
  else
    if [ -n "$SESSION_ID" ] && [ -n "$PROMPT" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — resuming Claude session $SESSION_ID with initial prompt: $PROMPT"
    elif [ -n "$SESSION_ID" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — resuming Claude session $SESSION_ID"
    elif [ -n "$PROMPT" ]; then
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — fresh Claude session with initial prompt: $PROMPT"
    else
      echo "iTerm2: opened new tab '$TAB_MARKER' in $DIR_ABS — fresh Claude session"
    fi
  fi
else
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
    echo "Terminal.app (iTerm2 not installed): opened new window in $DIR_ABS — fresh Claude session"
  fi
fi
