#!/usr/bin/env bash
# Setup Ralph Loop - Initialize iterative development loop
set -euo pipefail

LOOP_FILE=".claude/ralph-loop.local.md"

# Parse arguments
prompt=""
max_iterations=0
completion_promise=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-iterations)
            if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --max-iterations requires a positive integer" >&2
                exit 1
            fi
            max_iterations="$2"
            shift 2
            ;;
        --completion-promise)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --completion-promise requires a text argument" >&2
                exit 1
            fi
            completion_promise="$2"
            shift 2
            ;;
        *)
            if [[ -z "$prompt" ]]; then
                prompt="$1"
            else
                prompt="$prompt $1"
            fi
            shift
            ;;
    esac
done

# Validate prompt
if [[ -z "$prompt" ]]; then
    echo "Error: No prompt provided" >&2
    echo "Usage: /ralph-wiggum:ralph-loop \"Your task\" --max-iterations 30 --completion-promise \"DONE\"" >&2
    exit 1
fi

# Create .claude directory if needed
mkdir -p .claude

# Create loop state file
cat > "$LOOP_FILE" <<EOF
---
active: true
iteration: 1
max_iterations: $max_iterations
completion_promise: $completion_promise
started: $(date -Iseconds)
---

$prompt
EOF

# Output setup message
echo "Ralph loop activated!"
echo ""
if [[ "$max_iterations" -gt 0 ]]; then
    echo "Max iterations: $max_iterations"
else
    echo "WARNING: No max iterations set - loop runs indefinitely!"
fi
if [[ -n "$completion_promise" ]]; then
    echo "Completion promise: $completion_promise"
    echo ""
    echo "Output <promise>$completion_promise</promise> when the task is truly complete."
else
    echo "WARNING: No completion promise set - only max iterations will stop the loop!"
fi
echo ""
echo "Use /ralph-wiggum:cancel-ralph to manually stop the loop."
