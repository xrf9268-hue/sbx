#!/usr/bin/env bash
# .claude/scripts/session-start.sh - SessionStart hook for sbx-lite
#
# Smart session initialization with caching for efficiency.
# - First run: Installs deps and runs full validation
# - Subsequent runs: Quick status check only (~0.1s)
#
# Cache invalidation: Delete /tmp/sbx-session-* files to force re-check

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

# Cache keys based on project path
CACHE_DIR="${TMPDIR:-/tmp}"
PROJECT_HASH=$(echo "$PROJECT_DIR" | md5sum | cut -c1-8)
SETUP_MARKER="$CACHE_DIR/sbx-setup-done-$PROJECT_HASH"
BOOTSTRAP_CACHE="$CACHE_DIR/sbx-bootstrap-$PROJECT_HASH"

#==============================================================================
# Environment Detection
#==============================================================================

if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo "Desktop: Run 'bash hooks/install-hooks.sh' to set up git hooks."
    exit 0
fi

#==============================================================================
# First Run Setup (runs once, then cached)
#==============================================================================

first_run_setup() {
    echo "First run: Setting up sbx-lite environment..."

    # Install git hooks
    if [[ -x "hooks/install-hooks.sh" ]]; then
        bash hooks/install-hooks.sh > /dev/null 2>&1 && echo "  [OK] Git hooks" || echo "  [WARN] Git hooks"
    fi

    # Check and install essential deps
    local missing=()
    for dep in jq openssl; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  Installing: ${missing[*]}..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1 || true
        fi
    fi

    # Install shellcheck/shfmt (optional, best-effort)
    for tool in shellcheck shfmt; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            install_tool "$tool"
        fi
    done

    # Run bootstrap validation once
    if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
        if bash tests/unit/test_bootstrap_constants.sh > "$BOOTSTRAP_CACHE.log" 2>&1; then
            echo "OK" > "$BOOTSTRAP_CACHE"
            echo "  [OK] Bootstrap validation"
        else
            echo "FAIL" > "$BOOTSTRAP_CACHE"
            echo "  [FAIL] Bootstrap - see $BOOTSTRAP_CACHE.log"
        fi
    fi

    # Mark setup complete
    date +%s > "$SETUP_MARKER"
    echo "Setup complete."
}

install_tool() {
    local tool="$1"
    case "$tool" in
        shellcheck)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get install -y -qq shellcheck >/dev/null 2>&1 || true
            fi
            if ! command -v shellcheck >/dev/null 2>&1; then
                local ver="v0.10.0"
                wget -qO- "https://github.com/koalaman/shellcheck/releases/download/$ver/shellcheck-$ver.linux.x86_64.tar.xz" 2>/dev/null \
                    | tar -xJf - -C /tmp/ 2>/dev/null \
                    && sudo mv "/tmp/shellcheck-$ver/shellcheck" /usr/local/bin/ 2>/dev/null || true
            fi
            ;;
        shfmt)
            local ver="v3.10.0"
            wget -qO /tmp/shfmt "https://github.com/mvdan/sh/releases/download/$ver/shfmt_${ver}_linux_amd64" 2>/dev/null \
                && sudo mv /tmp/shfmt /usr/local/bin/shfmt && sudo chmod +x /usr/local/bin/shfmt 2>/dev/null || true
            ;;
    esac
}

#==============================================================================
# Quick Status Check (subsequent runs)
#==============================================================================

quick_status() {
    local status=()

    # Git hooks
    [[ -f ".git/hooks/pre-commit" ]] && status+=("hooks:OK") || status+=("hooks:MISS")

    # Essential deps
    local deps_ok=true
    for dep in jq openssl bash git; do
        command -v "$dep" >/dev/null 2>&1 || deps_ok=false
    done
    $deps_ok && status+=("deps:OK") || status+=("deps:MISS")

    # Bootstrap (from cache)
    if [[ -f "$BOOTSTRAP_CACHE" ]]; then
        [[ "$(cat "$BOOTSTRAP_CACHE")" == "OK" ]] && status+=("boot:OK") || status+=("boot:FAIL")
    fi

    # Branch info
    local branch commit
    branch=$(git branch --show-current 2>/dev/null || echo "?")
    commit=$(git log --oneline -1 2>/dev/null | cut -c1-7 || echo "?")

    echo "sbx: ${status[*]} | $branch ($commit)"

    # Show issues only if something is wrong
    if [[ ! -f ".git/hooks/pre-commit" ]] || ! $deps_ok; then
        echo "Issues: Run 'rm $SETUP_MARKER' then restart to re-setup"
    fi
}

#==============================================================================
# Main
#==============================================================================

# Check if setup already done (file exists and is less than 7 days old)
if [[ -f "$SETUP_MARKER" ]]; then
    setup_age=$(( $(date +%s) - $(cat "$SETUP_MARKER") ))
    if [[ $setup_age -lt 604800 ]]; then  # 7 days in seconds
        quick_status
        exit 0
    fi
fi

# First run or cache expired
first_run_setup
quick_status

exit 0
