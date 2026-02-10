#!/bin/bash

# Initialize a new sprint with directory structure and template files
# Usage: ./init-sprint.sh <sprintName> [--project-dir <path>] [ticket1] [ticket2] ...
# Example: ./init-sprint.sh sprint_1 TRIDENT-802 TRIDENT-803 TRIDENT-804
# Example: ./init-sprint.sh sprint_1 --project-dir ~/other-repo OTHER-123 OTHER-456

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default project directory
DEFAULT_PROJECT_DIR="~/BOATS-GROUP-PROJECTS-GITHUB/webapp-react-trident"

# Parse arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Sprint name is required${NC}"
    echo "Usage: ./init-sprint.sh <sprintName> [--project-dir <path>] [ticket1] [ticket2] ..."
    echo "Example: ./init-sprint.sh sprint_1 TRIDENT-802 TRIDENT-803 TRIDENT-804"
    echo "Example: ./init-sprint.sh sprint_1 --project-dir ~/other-repo OTHER-123 OTHER-456"
    echo ""
    echo "Default project directory: $DEFAULT_PROJECT_DIR"
    exit 1
fi

SPRINT_NAME="$1"
shift

# Check for --project-dir flag
PROJECT_DIR="$DEFAULT_PROJECT_DIR"
if [ "$1" = "--project-dir" ]; then
    shift
    if [ -z "$1" ]; then
        echo -e "${RED}Error: --project-dir requires a path${NC}"
        exit 1
    fi
    PROJECT_DIR="$1"
    shift
fi

TICKETS=("$@")

if [ ${#TICKETS[@]} -eq 0 ]; then
    echo -e "${RED}Error: At least one ticket is required${NC}"
    echo "Usage: ./init-sprint.sh <sprintName> [--project-dir <path>] [ticket1] [ticket2] ..."
    echo "Example: ./init-sprint.sh sprint_1 TRIDENT-802 TRIDENT-803 TRIDENT-804"
    exit 1
fi

BASE_DIR="$HOME/RalphLoops/SprintLoop"
SPRINTS_DIR="${BASE_DIR}/Sprints"
SPRINT_DIR="${SPRINTS_DIR}/${SPRINT_NAME}"

# Check if sprint already exists
if [ -d "$SPRINT_DIR" ]; then
    echo -e "${YELLOW}Warning: Sprint directory already exists: ${SPRINT_DIR}${NC}"
    echo ""
    echo "  1) Reset Sprint for Next Iteration (Run Failed Tasks)"
    echo "  2) Overwrite Sprint (Redo Entire Run)"
    echo "  3) Abort"
    echo ""
    read -p "Choose an option [1/2/3]: " choice

    case "$choice" in
        1)
            # Check if jq is installed
            if ! command -v jq &> /dev/null; then
                echo -e "${RED}Error: jq is required for this option but not installed.${NC}"
                echo "Install with: brew install jq"
                exit 1
            fi

            STATUS_FILE="${SPRINT_DIR}/sprintStatus.json"
            if [ ! -f "$STATUS_FILE" ]; then
                echo -e "${RED}Error: sprintStatus.json not found in ${SPRINT_DIR}${NC}"
                exit 1
            fi

            # Count tickets with errors
            ERROR_COUNT=$(jq '[to_entries[] | select(.value.errors == true)] | length' "$STATUS_FILE")

            if [ "$ERROR_COUNT" -eq 0 ]; then
                echo -e "${YELLOW}No tickets with errors found. Nothing to reset.${NC}"
                exit 0
            fi

            # Increment iteration and set completed to false for tickets with errors, remove finished.true
            jq 'to_entries | map(
                if .value.errors == true then
                    .value.iteration += 1 |
                    .value.completed = false |
                    del(.value.errors)
                else .
                end
            ) | from_entries' "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"

            rm -f "${SPRINT_DIR}/finished.true"

            echo -e "${GREEN}Reset ${ERROR_COUNT} failed ticket(s) for next iteration.${NC}"
            echo -e "${GREEN}Run ./sprint-loop.sh ${SPRINT_NAME} to retry.${NC}"
            exit 0
            ;;
        2)
            echo -e "${YELLOW}Overwriting sprint: ${SPRINT_NAME}${NC}"
            rm -rf "$SPRINT_DIR"
            ;;
        3)
            echo "Aborted."
            exit 1
            ;;
        *)
            echo -e "${RED}Invalid option. Aborted.${NC}"
            exit 1
            ;;
    esac
fi

# Create sprint directory
mkdir -p "$SPRINT_DIR"
echo -e "${GREEN}Created sprint directory: ${SPRINT_DIR}${NC}"

# Create learnings file
cat > "${SPRINT_DIR}/learnings.md" << EOF
# Sprint Learnings - ${SPRINT_NAME}

This file captures learnings accumulated during sprint execution.

---

EOF
echo -e "${GREEN}Created learnings.md${NC}"

# Create summary file
cat > "${SPRINT_DIR}/summary.md" << EOF
# Sprint Summary - ${SPRINT_NAME}

**Started:** Not yet started
**Status:** In Progress

---

EOF
echo -e "${GREEN}Created summary.md${NC}"

# Build sprintStatus.json and ticket directories
echo "{" > "${SPRINT_DIR}/sprintStatus.json"
PRIORITY=1
LAST_IDX=$((${#TICKETS[@]} - 1))

for i in "${!TICKETS[@]}"; do
    TICKET="${TICKETS[$i]}"

    # Add to JSON
    if [ $i -eq $LAST_IDX ]; then
        COMMA=""
    else
        COMMA=","
    fi

    cat >> "${SPRINT_DIR}/sprintStatus.json" << EOF
  "${TICKET}": {
    "priority": ${PRIORITY},
    "completed": false,
    "baseBranch": "main",
    "projectDir": "${PROJECT_DIR}",
    "iteration": 1
  }${COMMA}
EOF

    # Create ticket directory (context.md and plan.md created via /ticket-driver PLAN-MODE)
    TICKET_DIR="${SPRINT_DIR}/${TICKET}"
    mkdir -p "$TICKET_DIR"

    echo -e "${GREEN}Created ticket directory: ${TICKET}${NC}"
    PRIORITY=$((PRIORITY + 1))
done

echo "}" >> "${SPRINT_DIR}/sprintStatus.json"
echo -e "${GREEN}Created sprintStatus.json with ${#TICKETS[@]} tickets${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Sprint initialized: ${SPRINT_NAME}${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Project directory: ${PROJECT_DIR}"
echo ""
echo "Next steps:"
echo "1. For each ticket, run /ticket-driver in PLAN-MODE to generate context.md and plan.md:"
for TICKET in "${TICKETS[@]}"; do
    echo "   - ${TICKET}: /ticket-driver PLAN-MODE ${SPRINT_NAME} ${TICKET}"
done
echo ""
echo "2. (Optional) Edit sprintStatus.json to change baseBranch or projectDir if needed:"
echo "   - baseBranch: default is 'main' for all tickets"
echo "   - projectDir: default is '${PROJECT_DIR}'"
echo "   ${SPRINT_DIR}/sprintStatus.json"
echo ""
echo "3. Run the sprint loop from the sandboxed run directory:"
echo "   mkdir -p ~/RalphLoops/run && cd ~/RalphLoops/run"
echo "   ~/RalphLoops/SprintLoop/sprint-loop.sh ${SPRINT_NAME}"
