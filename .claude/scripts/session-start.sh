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

# 2. Verify Dependencies
# Essential deps (required for core functionality)
essential_deps=(jq openssl bash git)
# Optional deps (code quality tools - nice to have)
optional_deps=(shellcheck shfmt)

essential_missing=()
optional_missing=()

for dep in "${essential_deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        essential_missing+=("$dep")
    fi
done

for dep in "${optional_deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        optional_missing+=("$dep")
    fi
done

# Try to install missing essential dependencies
if [[ ${#essential_missing[@]} -gt 0 ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "${essential_missing[@]}" >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q "${essential_missing[@]}" >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet "${essential_missing[@]}" >/dev/null 2>&1 || true
    fi
fi

# Try to install shellcheck (available via apt/yum/apk)
if [[ " ${optional_missing[*]} " =~ " shellcheck " ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y -qq shellcheck >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q ShellCheck >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet shellcheck >/dev/null 2>&1 || true
    fi
fi

# Try to install shfmt (NOT in apt - use snap, go, or direct binary)
if [[ " ${optional_missing[*]} " =~ " shfmt " ]]; then
    if command -v snap >/dev/null 2>&1; then
        sudo snap install shfmt >/dev/null 2>&1 || true
    elif command -v go >/dev/null 2>&1; then
        go install mvdan.cc/sh/v3/cmd/shfmt@latest >/dev/null 2>&1 || true
        # Add Go bin to PATH for this session and future commands
        export PATH="$PATH:$HOME/go/bin"
        if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
            echo "export PATH=\"\$PATH:\$HOME/go/bin\"" >> "$CLAUDE_ENV_FILE"
        fi
    else
        # Direct binary download as last resort
        SHFMT_VERSION="v3.10.0"
        if wget -qO /tmp/shfmt "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64" 2>/dev/null; then
            sudo mv /tmp/shfmt /usr/local/bin/shfmt && sudo chmod +x /usr/local/bin/shfmt
        fi
    fi
fi

# Try to install shellcheck via direct binary if apt failed
if [[ " ${optional_missing[*]} " =~ " shellcheck " ]] && ! command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_VERSION="v0.10.0"
    if wget -qO- "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" 2>/dev/null | tar -xJf - -C /tmp/ 2>/dev/null; then
        sudo mv "/tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ && sudo chmod +x /usr/local/bin/shellcheck
    fi
fi

# Re-check after installation attempts (include Go bin in PATH)
export PATH="$PATH:$HOME/go/bin:/usr/local/bin"
still_missing_essential=()
still_missing_optional=()

for dep in "${essential_deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        still_missing_essential+=("$dep")
    fi
done

for dep in "${optional_deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        still_missing_optional+=("$dep")
    fi
done

# Determine status
if [[ ${#still_missing_essential[@]} -eq 0 ]]; then
    if [[ ${#still_missing_optional[@]} -eq 0 ]]; then
        setup_status+=("deps:✓")
    else
        setup_status+=("deps:✓")
        setup_errors+=("Missing: ${still_missing_optional[*]}")
    fi
else
    setup_status+=("deps:✗")
    setup_errors+=("Missing essential: ${still_missing_essential[*]}")
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
