#!/usr/bin/env bash
# .claude/scripts/session-start.sh - SessionStart hook for sbx-lite
#
# Lightweight status check - runs on every session start.
# For one-time setup (dependency installation), see setup.sh
#
# Environment: Claude Code web/iOS (CLAUDE_CODE_REMOTE=true)

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

#==============================================================================
# Environment Detection
#==============================================================================

if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo "Desktop: Run 'bash hooks/install-hooks.sh' to set up git hooks."
    exit 0
fi

#==============================================================================
# Quick Status Checks (no installations)
#==============================================================================

status=()
issues=()

# 1. Check git hooks
if [[ -f ".git/hooks/pre-commit" ]]; then
    status+=("hooks:OK")
else
    status+=("hooks:MISSING")
    issues+=("Run: claude --init (or bash hooks/install-hooks.sh)")
fi

# 2. Check essential deps
essential_missing=()
for dep in jq openssl bash git; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        essential_missing+=("$dep")
    fi
done

if [[ ${#essential_missing[@]} -eq 0 ]]; then
    status+=("deps:OK")
else
    status+=("deps:MISSING")
    issues+=("Missing: ${essential_missing[*]} - Run: claude --init")
fi

# 3. Check optional tools
optional_missing=()
for dep in shellcheck shfmt; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        optional_missing+=("$dep")
    fi
done

if [[ ${#optional_missing[@]} -gt 0 ]]; then
    issues+=("Optional missing: ${optional_missing[*]}")
fi

# 4. Validate bootstrap constants (quick check)
if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
    if bash tests/unit/test_bootstrap_constants.sh > /tmp/bootstrap-validation.log 2>&1; then
        status+=("bootstrap:OK")
    else
        status+=("bootstrap:FAIL")
        issues+=("Bootstrap validation failed - see /tmp/bootstrap-validation.log")
    fi
fi

#==============================================================================
# Output: Concise Summary
#==============================================================================

# Get branch info
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    commit=$(git log --oneline -1 2>/dev/null | cut -c1-50 || echo "unknown")
else
    branch="not-a-repo"
    commit="N/A"
fi

echo "sbx-lite: ${status[*]}"
echo "Branch: $branch | $commit"

if [[ ${#issues[@]} -gt 0 ]]; then
    echo "Issues:"
    for issue in "${issues[@]}"; do
        echo "  - $issue"
    done
fi

exit 0
