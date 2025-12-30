#!/usr/bin/env bash
# Combined Stop Hook: Ralph Loop + Handoff Reminder
# Runs ralph-loop check first, then handoff reminder if not blocked
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Check Ralph Loop (may block exit)
RALPH_OUTPUT=$("$SCRIPT_DIR/ralph-stop-hook.sh" 2>&1) || true

# If ralph hook returned JSON with "block", output it and exit
if echo "$RALPH_OUTPUT" | grep -q '"decision": "block"'; then
    echo "$RALPH_OUTPUT"
    exit 0
fi

# Step 2: Run handoff reminder (if ralph didn't block)
"$SCRIPT_DIR/stop-hook-handoff-reminder.sh" 2>&1 || true

exit 0
