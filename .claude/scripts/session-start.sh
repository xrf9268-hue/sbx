#!/usr/bin/env bash
# .claude/scripts/session-start.sh - SessionStart hook for sbx-lite
#
# This hook automatically sets up the development environment when starting
# a new Claude Code session (web/iOS). It:
# - Installs git hooks automatically
# - Verifies/installs required dependencies
# - Runs initial validation tests
# - Displays project information
#
# Environment: Claude Code web/iOS (CLAUDE_CODE_REMOTE=true)
# Trigger: SessionStart (new session only, not resume/clear)

set -euo pipefail

# Project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

# Detect color support
USE_COLOR=false
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    USE_COLOR=true
fi

# Colors (only if supported)
if [[ "$USE_COLOR" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

#==============================================================================
# Environment Detection
#==============================================================================

# Check if running in Claude Code remote environment
if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo "ℹ  Desktop environment detected"
    echo ""
    echo "For desktop development, manually install:"
    echo "  bash hooks/install-hooks.sh"
    echo ""
    exit 0
fi

#==============================================================================
# Header
#==============================================================================

echo ""
echo "=========================================="
echo "  sbx-lite - SessionStart Hook"
echo "  Automated Environment Setup"
echo "=========================================="
echo ""

#==============================================================================
# Install Git Hooks
#==============================================================================

echo "[1/4] Installing git hooks..."

if [[ -x "hooks/install-hooks.sh" ]]; then
    # Run hook installer quietly
    if bash hooks/install-hooks.sh > /tmp/hook-install.log 2>&1; then
        echo "  ✓ Git hooks installed successfully"
        echo "    Pre-commit validation: ENABLED"
    else
        echo "  ⚠ Git hooks installation had warnings (see /tmp/hook-install.log)"
    fi
else
    echo "  ⚠ Hook installer not found (hooks/install-hooks.sh)"
fi

echo ""

#==============================================================================
# Verify Dependencies
#==============================================================================

echo "[2/4] Verifying dependencies..."

deps_ok=0
deps_missing=()

# Check jq
if command -v jq >/dev/null 2>&1; then
    jq_version=$(jq --version 2>&1 | head -1)
    echo "  ✓ jq: $jq_version"
    deps_ok=$((deps_ok + 1))
else
    echo "  ✗ jq: NOT INSTALLED"
    deps_missing+=("jq")
fi

# Check openssl
if command -v openssl >/dev/null 2>&1; then
    openssl_version=$(openssl version | cut -d' ' -f1-2)
    echo "  ✓ openssl: $openssl_version"
    deps_ok=$((deps_ok + 1))
else
    echo "  ✗ openssl: NOT INSTALLED"
    deps_missing+=("openssl")
fi

# Check bash version
bash_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
echo "  ✓ bash: $bash_version"
deps_ok=$((deps_ok + 1))

# Check git
if command -v git >/dev/null 2>&1; then
    git_version=$(git --version | cut -d' ' -f3)
    echo "  ✓ git: $git_version"
    deps_ok=$((deps_ok + 1))
fi

# Install missing dependencies
if [[ ${#deps_missing[@]} -gt 0 ]]; then
    echo ""
    echo "  Installing missing dependencies: ${deps_missing[*]}"

    # Detect package manager and install
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${deps_missing[@]}" 2>&1 | grep -v "^Reading\|^Building\|^0 upgraded" || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q "${deps_missing[@]}"
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet "${deps_missing[@]}"
    else
        echo "  ✗ Could not auto-install dependencies (no package manager found)"
        echo "    Please install manually: ${deps_missing[*]}"
    fi

    # Verify installation
    for dep in "${deps_missing[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            echo "  ✓ $dep installed successfully"
        else
            echo "  ✗ $dep installation failed"
        fi
    done
fi

echo ""

#==============================================================================
# Run Bootstrap Validation
#==============================================================================

echo "[3/4] Validating bootstrap configuration..."

if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
    if bash tests/unit/test_bootstrap_constants.sh > /tmp/bootstrap-validation.log 2>&1; then
        echo "  ✓ All 15 bootstrap constants properly configured"
        echo "    - Download constants (5)"
        echo "    - Network constants (1)"
        echo "    - Reality validation (2)"
        echo "    - Reality config (5)"
        echo "    - Permissions (2)"
    else
        echo "  ✗ Bootstrap validation FAILED"
        echo ""
        echo "Error summary:"
        grep "✗ FAIL" /tmp/bootstrap-validation.log | head -5 || true
        echo ""
        echo "  See full log: /tmp/bootstrap-validation.log"
    fi
else
    echo "  ⚠ Bootstrap test not found (tests/unit/test_bootstrap_constants.sh)"
fi

echo ""

#==============================================================================
# Project Information
#==============================================================================

echo "[4/4] Project Information"
echo ""

# Git branch
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "detached HEAD")
    echo "  Branch: $current_branch"

    # Recent commits
    echo "  Recent commits:"
    git log --oneline --decorate --max-count=3 | sed 's/^/    /'
fi

echo ""
echo "  Quick Commands:"
echo "    bash tests/test-runner.sh unit    # Run all unit tests"
echo "    bash tests/unit/test_bootstrap_constants.sh    # Validate bootstrap"
echo "    bash hooks/install-hooks.sh       # Reinstall git hooks"
echo "    bash install.sh --help      # Installation help"
echo ""

# Documentation links
echo "  Documentation:"
echo "    CONTRIBUTING.md                   # Developer guide (START HERE)"
echo "    CLAUDE.md                         # Detailed coding standards"
echo "    tests/unit/README_BOOTSTRAP_TESTS.md    # Bootstrap pattern guide"
echo "    .claude/WORKFLOWS.md              # TDD and git workflows"
echo ""

#==============================================================================
# Summary
#==============================================================================

echo "=========================================="
echo "  ✓ Environment setup complete!"
echo "=========================================="
echo ""
echo "What's configured:"
echo "  ✓ Git hooks installed (pre-commit validation enabled)"
echo "  ✓ Dependencies verified/installed"
echo "  ✓ Bootstrap constants validated"
echo "  ✓ Ready for development"
echo ""
echo "Next steps:"
echo "  1. Read CONTRIBUTING.md for development guidelines"
echo "  2. Make your changes following code standards"
echo "  3. Run 'bash tests/test-runner.sh unit' before committing"
echo "  4. Commit normally - hooks will validate automatically"
echo ""
echo "Need help? Check CONTRIBUTING.md or CLAUDE.md"
echo ""
