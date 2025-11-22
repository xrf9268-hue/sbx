#!/usr/bin/env bash
set -euo pipefail

# Stop Hook: Intelligent Handoff Reminder
# Analyzes session to determine if a handoff should be created
# Usage: Called automatically by Claude Code on Stop event

# ============================================================================
# Configuration
# ============================================================================

readonly HANDOFFS_DIR=".claude/handoffs"
readonly MIN_CONVERSATION_LENGTH=10  # Minimum messages to suggest handoff

# Colors
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" >&2
}

log_reminder() {
    echo -e "${YELLOW}💡${NC} $*" >&2
}

# Count conversation turns (rough estimate of complexity)
count_conversation_turns() {
    local transcript="$1"

    if [[ ! -f "$transcript" ]]; then
        echo "0"
        return
    fi

    # Count user and assistant messages
    local count
    count=$(grep -c '"role":\s*"user"\|"role":\s*"assistant"' "$transcript" 2>/dev/null || echo "0")
    echo "$count"
}

# Check if recent handoff already exists
has_recent_handoff() {
    [[ ! -d "$HANDOFFS_DIR" ]] && return 1

    # Check for handoffs created in last 30 minutes
    local recent
    recent=$(find "$HANDOFFS_DIR" -name "*.md" -type f -mmin -30 2>/dev/null | wc -l)

    [[ $recent -gt 0 ]]
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    # Read hook input from stdin
    local input
    input=$(cat)

    # Parse JSON input
    local transcript_path
    local stop_hook_active

    transcript_path=$(echo "$input" | grep -o '"transcript_path":\s*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' || echo "")
    stop_hook_active=$(echo "$input" | grep -o '"stop_hook_active":\s*\(true\|false\)' | sed 's/.*:\s*\(.*\)/\1/' || echo "false")

    # Don't run if stop hook already active (prevent loops)
    if [[ "$stop_hook_active" == "true" ]]; then
        exit 0
    fi

    # Count conversation complexity
    local conversation_length
    conversation_length=$(count_conversation_turns "$transcript_path")

    # Skip reminder for short conversations
    if [[ $conversation_length -lt $MIN_CONVERSATION_LENGTH ]]; then
        exit 0
    fi

    # Skip if recent handoff already created
    if has_recent_handoff; then
        exit 0
    fi

    # Show reminder (stderr goes to user, not Claude)
    echo "" >&2
    log_reminder "This session had ${conversation_length} conversation turns." >&2
    log_info "Consider creating a handoff to preserve context:" >&2
    echo "    /handoff \"describe what you accomplished\"" >&2
    echo "" >&2

    # Exit 0: Allow stop to proceed, just show reminder
    exit 0
}

main "$@"
