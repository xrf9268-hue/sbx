#!/usr/bin/env bash
# Stop Hook: Handoff Reminder
# Reminds user to create handoff for complex sessions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run handoff reminder
"$SCRIPT_DIR/stop-hook-handoff-reminder.sh" 2>&1 || true

exit 0
