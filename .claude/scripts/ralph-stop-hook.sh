#!/usr/bin/env bash
# Ralph Wiggum Stop Hook
# Implements self-referential loops by intercepting session exit
set -euo pipefail

LOOP_FILE=".claude/ralph-loop.local.md"

# Check if ralph loop is active
if [[ ! -f "$LOOP_FILE" ]]; then
    exit 0
fi

# Read loop configuration from frontmatter
active=$(grep "^active:" "$LOOP_FILE" 2>/dev/null | sed 's/active: //' || echo "false")
if [[ "$active" != "true" ]]; then
    exit 0
fi

iteration=$(grep "^iteration:" "$LOOP_FILE" 2>/dev/null | sed 's/iteration: //' || echo "0")
max_iterations=$(grep "^max_iterations:" "$LOOP_FILE" 2>/dev/null | sed 's/max_iterations: //' || echo "0")
completion_promise=$(grep "^completion_promise:" "$LOOP_FILE" 2>/dev/null | sed 's/completion_promise: //' || echo "")

# Validate numeric fields
if ! [[ "$iteration" =~ ^[0-9]+$ ]] || ! [[ "$max_iterations" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid iteration values in loop file. Cleaning up." >&2
    rm -f "$LOOP_FILE"
    exit 0
fi

# Check max iterations
if [[ "$max_iterations" -gt 0 ]] && [[ "$iteration" -ge "$max_iterations" ]]; then
    echo "Ralph loop reached max iterations ($max_iterations). Stopping." >&2
    rm -f "$LOOP_FILE"
    exit 0
fi

# Check for completion promise in transcript
TRANSCRIPT_FILE="${CLAUDE_TRANSCRIPT_FILE:-}"
if [[ -n "$completion_promise" ]] && [[ -n "$TRANSCRIPT_FILE" ]] && [[ -f "$TRANSCRIPT_FILE" ]]; then
    if grep -q "<promise>$completion_promise</promise>" "$TRANSCRIPT_FILE" 2>/dev/null; then
        echo "Completion promise found! Ralph loop complete." >&2
        rm -f "$LOOP_FILE"
        exit 0
    fi
fi

# Increment iteration
new_iteration=$((iteration + 1))

# Extract prompt (everything after the frontmatter)
prompt=$(awk '/^---$/{if(++c==2){getline; found=1}} found' "$LOOP_FILE")

# Update iteration in loop file
sed -i "s/^iteration: .*/iteration: $new_iteration/" "$LOOP_FILE"

# Output JSON to block exit and continue with prompt
cat <<EOF
{
  "decision": "block",
  "reason": "$prompt",
  "systemMessage": "[Ralph Loop - Iteration $new_iteration of ${max_iterations:-∞}] Continue working on the task. Review your previous work and iterate."
}
EOF
