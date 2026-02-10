#!/bin/bash

# Sprint Loop - Runs ralph loop iterations until all sprint tasks are complete
# Usage: ./sprint-loop.sh <sprintName> [--watchMode]
# Example: ./sprint-loop.sh sprint_1
# Example: ./sprint-loop.sh sprint_1 --watchMode

set -e

# Exit cleanly on Ctrl+C
trap 'echo -e "\n${RED}Sprint loop interrupted by user${NC}"; exit 130' INT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Format seconds to minutes and seconds
format_duration() {
    local total_seconds=$1
    local minutes=$((total_seconds / 60))
    local seconds=$((total_seconds % 60))
    if [ $minutes -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Validate arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Sprint name is required${NC}"
    echo "Usage: ./sprint-loop.sh <sprintName> [--watchMode]"
    echo "Example: ./sprint-loop.sh sprint_1"
    echo "Example: ./sprint-loop.sh sprint_1 --watchMode"
    exit 1
fi

SPRINT_NAME="$1"
WATCH_MODE=false
if [ "$2" = "--watchMode" ]; then
    WATCH_MODE=true
fi
BASE_DIR="$HOME/RalphLoops/SprintLoop"
SPRINTS_DIR="${BASE_DIR}/Sprints"
SPRINT_DIR="${SPRINTS_DIR}/${SPRINT_NAME}"
PROMPT_FILE="${BASE_DIR}/prompt.md"
FINISHED_FILE="${SPRINT_DIR}/finished.true"
STATUS_FILE="${SPRINT_DIR}/sprintStatus.json"

# Validate prompt file exists (in base directory)
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}Error: Prompt file does not exist: ${PROMPT_FILE}${NC}"
    exit 1
fi

# Validate sprint directory exists
if [ ! -d "$SPRINT_DIR" ]; then
    echo -e "${RED}Error: Sprint directory does not exist: ${SPRINT_DIR}${NC}"
    echo "Run init-sprint.sh first to create the sprint."
    exit 1
fi

# Validate status file exists
if [ ! -f "$STATUS_FILE" ]; then
    echo -e "${RED}Error: Sprint status file does not exist: ${STATUS_FILE}${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Validate learnings file exists
if [ ! -f "${SPRINT_DIR}/learnings.md" ]; then
    echo -e "${RED}Error: learnings.md not found in ${SPRINT_DIR}${NC}"
    echo "Run init-sprint.sh first to create the sprint."
    exit 1
fi

# Track iteration count
ITERATION=0
START_TIME=$(date +%s)

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Starting Sprint Loop: ${SPRINT_NAME}${NC}"
echo -e "${BLUE}Started at: $(date)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Main loop - continue until finished.true exists
while [ ! -f "$FINISHED_FILE" ]; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)

    echo -e "${YELLOW}--------------------------------------------${NC}"
    echo -e "${YELLOW}Iteration ${ITERATION} - $(date)${NC}"
    echo -e "${YELLOW}--------------------------------------------${NC}"

    # Find next incomplete ticket (lowest priority with completed=false)
    NEXT_TICKET=$(jq -r '
        to_entries
        | map(select(.value.completed == false))
        | sort_by(.value.priority)
        | .[0].key // empty' "$STATUS_FILE")

    # If no incomplete tickets, create finished.true and exit
    if [ -z "$NEXT_TICKET" ]; then
        echo -e "${GREEN}All tickets complete! Creating finished.true${NC}"
        echo "Sprint complete - $(date)" > "$FINISHED_FILE"
        break
    fi

    echo -e "${BLUE}Next ticket: ${NEXT_TICKET}${NC}"

    # Get projectDir for this ticket
    PROJECT_DIR=$(jq -r --arg ticket "$NEXT_TICKET" '.[$ticket].projectDir // empty' "$STATUS_FILE")

    if [ -z "$PROJECT_DIR" ]; then
        echo -e "${RED}Error: No projectDir specified for ${NEXT_TICKET}${NC}"
        exit 1
    fi

    # Expand ~ to $HOME
    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"

    # Validate project directory exists
    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${RED}Error: Project directory does not exist: ${PROJECT_DIR}${NC}"
        exit 1
    fi

    echo -e "${BLUE}Project directory: ${PROJECT_DIR}${NC}"

    # Generate a session ID and record start time in sprintStatus.json
    SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    STARTED_AT=$(date +"%Y-%m-%dT%H:%M:%S")
    jq --arg ticket "$NEXT_TICKET" --arg sid "$SESSION_ID" --arg started "$STARTED_AT" \
        '.[$ticket].sessionId = $sid | .[$ticket].startedAt = $started | .[$ticket].completedAt = null' \
        "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    echo -e "${BLUE}Session ID: ${SESSION_ID}${NC}"
    echo -e "${BLUE}Started at: ${STARTED_AT}${NC}"

    # Run ralph loop with the prompt file
    # Permissions aligned with ~/.claude/settings.json and project settings
    ALLOWED_TOOLS=$(cat << 'TOOLS'
Edit,Write,Read,Glob,Grep,MultiEdit,Task,
Bash(git status*),Bash(git pull*),Bash(git fetch*),Bash(git merge*),Bash(git branch*),Bash(git checkout*),
Bash(git log*),Bash(git add*),Bash(git commit*),Bash(git push*),Bash(git diff*),Bash(git show*),
Bash(git stash*),Bash(git reset*),Bash(git rm*),Bash(git mv*),Bash(git rev-parse*),
Bash(npm test*),Bash(npm run*),Bash(npm install*),Bash(npm i *),Bash(npm ls*),Bash(npm version*),
Bash(CI=true npm test*),Bash(env CI=true npm test*),
Bash(npx firebase*),Bash(firebase deploy*),Bash(npx tsc*),Bash(npx ts-node*),
Bash(gh pr create*),Bash(gh pr view*),Bash(gh pr diff*),Bash(gh pr list*),Bash(gh pr checks*),Bash(gh api*),
Bash(curl*),Bash(node*),Bash(mkdir*),Bash(touch*),Bash(ls*),Bash(cat*),
mcp__atlassian__*,mcp__context7__*,mcp__sequential-thinking__*,
WebSearch,WebFetch
TOOLS
)
    # Remove newlines from ALLOWED_TOOLS
    ALLOWED_TOOLS=$(echo "$ALLOWED_TOOLS" | tr -d '\n' | tr -s ' ')

    # Substitute all template variables in prompt
    PROCESSED_PROMPT=$(sed \
        -e "s|{{SPRINT_NAME}}|${SPRINT_NAME}|g" \
        -e "s|{{JIRA_TICKET}}|${NEXT_TICKET}|g" \
        -e "s|{{PROJECT_DIR}}|${PROJECT_DIR}|g" \
        "$PROMPT_FILE")

    # Run claude from the project directory, with sprint dir as additional allowed directory
    LOG_FILE="${SPRINT_DIR}/${NEXT_TICKET}/output.log"
    if [ "$WATCH_MODE" = true ]; then
        echo -e "${BLUE}Watch mode: streaming Claude output to terminal${NC}"
        echo -e "${BLUE}Output also logged to: ${LOG_FILE}${NC}"
        # Use stream-json for real-time output; tee to log file
        # jq --unbuffered extracts assistant text as it arrives
        echo "$PROCESSED_PROMPT" | \
            (cd "$PROJECT_DIR" && claude \
                --session-id "$SESSION_ID" \
                --allowedTools "$ALLOWED_TOOLS" \
                --add-dir "$SPRINT_DIR" \
                --print \
                --verbose \
                --output-format stream-json) 2>&1 | tee "$LOG_FILE"
    else
        echo -e "${BLUE}Output logged to: ${LOG_FILE}${NC}"
        echo "$PROCESSED_PROMPT" | \
            (cd "$PROJECT_DIR" && claude \
                --session-id "$SESSION_ID" \
                --allowedTools "$ALLOWED_TOOLS" \
                --add-dir "$SPRINT_DIR" \
                --print) > "$LOG_FILE" 2>&1
    fi

    # Record completion time in sprintStatus.json
    COMPLETED_AT=$(date +"%Y-%m-%dT%H:%M:%S")
    jq --arg ticket "$NEXT_TICKET" --arg completed "$COMPLETED_AT" \
        '.[$ticket].completedAt = $completed' "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))

    echo ""
    echo -e "${GREEN}Iteration ${ITERATION} completed in $(format_duration ${ITER_DURATION})${NC}"
    echo ""

    # Small delay between iterations to prevent hammering
    if [ ! -f "$FINISHED_FILE" ]; then
        echo -e "${BLUE}Waiting 5 seconds before next iteration...${NC}"
        sleep 5
    fi
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Sprint Loop Complete!${NC}"
echo -e "${GREEN}Total iterations: ${ITERATION}${NC}"
echo -e "${GREEN}Total duration: $(format_duration ${TOTAL_DURATION})${NC}"
echo -e "${GREEN}Finished at: $(date)${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Summary available at: ${SPRINT_DIR}/summary.md"
echo -e "Learnings available at: ${SPRINT_DIR}/learnings.md"
