#!/usr/bin/env bash
set -euo pipefail

# SessionEnd Hook: Optional Cleanup for Handoffs
# Performs gentle cleanup tasks when session ends
# Usage: Called automatically by Claude Code on SessionEnd event

# ============================================================================
# Configuration
# ============================================================================

readonly HANDOFFS_DIR=".claude/handoffs"
readonly AUTO_ARCHIVE_DAYS=90  # Auto-archive handoffs older than this

# ============================================================================
# Helper Functions
# ============================================================================

# Get age of file in days
get_file_age_days() {
    local file="$1"
    local now
    local mtime
    local age_seconds

    now=$(date +%s)

    # Cross-platform modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mtime=$(stat -f %m "$file")
    else
        mtime=$(stat -c %Y "$file")
    fi

    age_seconds=$((now - mtime))
    echo $((age_seconds / 86400))
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    # Read hook input from stdin
    local input
    input=$(cat)

    # Only run cleanup on normal exit (not on crash or logout)
    local reason
    reason=$(echo "$input" | grep -o '"reason":\s*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' || echo "other")

    if [[ "$reason" != "clear" && "$reason" != "other" ]]; then
        # Don't cleanup on logout or unusual exits
        exit 0
    fi

    [[ ! -d "$HANDOFFS_DIR" ]] && exit 0

    # Auto-archive very old handoffs
    local archive_dir="${HANDOFFS_DIR}/archive"
    local archived_count=0

    for file in "${HANDOFFS_DIR}"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "README.md" ]] && continue

        local age
        age=$(get_file_age_days "$file")

        if [[ $age -ge $AUTO_ARCHIVE_DAYS ]]; then
            mkdir -p "$archive_dir"
            mv "$file" "$archive_dir/"
            ((archived_count++))
        fi
    done

    # Report cleanup (only if something happened)
    if [[ $archived_count -gt 0 ]]; then
        echo "🗂️  Auto-archived $archived_count old handoff(s) (>$AUTO_ARCHIVE_DAYS days)" >&2
    fi

    exit 0
}

main "$@"
