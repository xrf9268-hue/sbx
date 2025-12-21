#!/usr/bin/env bash
# .claude/scripts/session-start.sh - SessionStart hook for sbx-lite
#
# Optimized for minimal context window usage while providing essential
# environment information to Claude.
#
# Environment: Claude Code web/iOS (CLAUDE_CODE_REMOTE=true)
# Trigger: SessionStart (new session only, not resume/clear)

set -euo pipefail

# Project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

#==============================================================================
# Environment Detection
#==============================================================================

# Desktop environment - provide minimal guidance
if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo "Desktop environment: Run 'bash hooks/install-hooks.sh' to set up git hooks."
    exit 0
fi

#==============================================================================
# Setup Tasks (run silently, only report results)
#==============================================================================

setup_status=()
setup_errors=()

# 1. Install Git Hooks
if [[ -x "hooks/install-hooks.sh" ]]; then
    if bash hooks/install-hooks.sh > /tmp/hook-install.log 2>&1; then
        setup_status+=("git-hooks:✓")
    else
        setup_status+=("git-hooks:⚠")
        setup_errors+=("Git hooks: warnings in /tmp/hook-install.log")
    fi
else
    setup_status+=("git-hooks:⚠")
    setup_errors+=("Git hooks installer not found")
fi

# 2. Verify Dependencies (essential + code quality tools)
deps_missing=()
for dep in jq openssl bash git shellcheck shfmt; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        deps_missing+=("$dep")
    fi
done

if [[ ${#deps_missing[@]} -eq 0 ]]; then
    setup_status+=("deps:✓")
else
    # Try to install missing dependencies
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "${deps_missing[@]}" >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q "${deps_missing[@]}" >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet "${deps_missing[@]}" >/dev/null 2>&1 || true
    fi

    # Re-check after installation attempt
    still_missing=()
    for dep in "${deps_missing[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            still_missing+=("$dep")
        fi
    done

    if [[ ${#still_missing[@]} -eq 0 ]]; then
        setup_status+=("deps:✓(installed)")
    else
        setup_status+=("deps:✗")
        setup_errors+=("Missing: ${still_missing[*]}")
    fi
fi

# 3. Validate Bootstrap Constants
if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
    if bash tests/unit/test_bootstrap_constants.sh > /tmp/bootstrap-validation.log 2>&1; then
        setup_status+=("bootstrap:✓")
    else
        setup_status+=("bootstrap:✗")
        setup_errors+=("Bootstrap validation failed (see /tmp/bootstrap-validation.log)")
    fi
else
    setup_status+=("bootstrap:⚠")
    setup_errors+=("Bootstrap test not found")
fi

#==============================================================================
# Output: Concise Summary for Claude
#==============================================================================

# Get branch info
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    latest_commit=$(git log --oneline --max-count=1 2>/dev/null | cut -c1-50 || echo "unknown")
else
    branch="not-a-repo"
    latest_commit="N/A"
fi

# Build concise output
echo "sbx-lite development environment initialized:"
echo "• Status: ${setup_status[*]}"
echo "• Branch: $branch"
echo "• Latest: $latest_commit"
echo "• Tests: bash tests/test-runner.sh unit"
echo "• Hooks: bash hooks/install-hooks.sh"
echo "• Docs: CONTRIBUTING.md, CLAUDE.md, .claude/WORKFLOWS.md"

# Report errors if any
if [[ ${#setup_errors[@]} -gt 0 ]]; then
    echo "• Issues:"
    for error in "${setup_errors[@]}"; do
        echo "  - $error"
    done
fi

exit 0
