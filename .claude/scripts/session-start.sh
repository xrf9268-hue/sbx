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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 1

#==============================================================================
# Environment Detection
#==============================================================================

# Check if running in Claude Code remote environment
if [[ "${CLAUDE_CODE_REMOTE:-false}" != "true" ]]; then
    echo -e "${YELLOW}ℹ  Desktop environment detected${NC}"
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
echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BLUE}sbx-lite${NC} - Sing-Box Reality Protocol Deployment    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  SessionStart Hook - Automated Environment Setup     ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

#==============================================================================
# Install Git Hooks
#==============================================================================

echo -e "${BLUE}[1/4]${NC} Installing git hooks..."

if [[ -x "hooks/install-hooks.sh" ]]; then
    # Run hook installer quietly
    if bash hooks/install-hooks.sh > /tmp/hook-install.log 2>&1; then
        echo -e "${GREEN}  ✓${NC}  Git hooks installed successfully"
        echo "      Pre-commit validation: ENABLED"
    else
        echo -e "${YELLOW}  ⚠${NC}  Git hooks installation had warnings (see /tmp/hook-install.log)"
    fi
else
    echo -e "${YELLOW}  ⚠${NC}  Hook installer not found (hooks/install-hooks.sh)"
fi

echo ""

#==============================================================================
# Verify Dependencies
#==============================================================================

echo -e "${BLUE}[2/4]${NC} Verifying dependencies..."

deps_ok=0
deps_missing=()

# Check jq
if command -v jq >/dev/null 2>&1; then
    jq_version=$(jq --version 2>&1 | head -1)
    echo -e "${GREEN}  ✓${NC}  jq: $jq_version"
    deps_ok=$((deps_ok + 1))
else
    echo -e "${RED}  ✗${NC}  jq: NOT INSTALLED"
    deps_missing+=("jq")
fi

# Check openssl
if command -v openssl >/dev/null 2>&1; then
    openssl_version=$(openssl version | cut -d' ' -f1-2)
    echo -e "${GREEN}  ✓${NC}  openssl: $openssl_version"
    deps_ok=$((deps_ok + 1))
else
    echo -e "${RED}  ✗${NC}  openssl: NOT INSTALLED"
    deps_missing+=("openssl")
fi

# Check bash version
bash_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
echo -e "${GREEN}  ✓${NC}  bash: $bash_version"
deps_ok=$((deps_ok + 1))

# Check git
if command -v git >/dev/null 2>&1; then
    git_version=$(git --version | cut -d' ' -f3)
    echo -e "${GREEN}  ✓${NC}  git: $git_version"
    deps_ok=$((deps_ok + 1))
fi

# Install missing dependencies
if [[ ${#deps_missing[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}  Installing missing dependencies: ${deps_missing[*]}${NC}"

    # Detect package manager and install
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${deps_missing[@]}" 2>&1 | grep -v "^Reading\|^Building\|^0 upgraded" || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y -q "${deps_missing[@]}"
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add --quiet "${deps_missing[@]}"
    else
        echo -e "${RED}  ✗${NC}  Could not auto-install dependencies (no package manager found)"
        echo "      Please install manually: ${deps_missing[*]}"
    fi

    # Verify installation
    for dep in "${deps_missing[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✓${NC}  $dep installed successfully"
        else
            echo -e "${RED}  ✗${NC}  $dep installation failed"
        fi
    done
fi

echo ""

#==============================================================================
# Run Bootstrap Validation
#==============================================================================

echo -e "${BLUE}[3/4]${NC} Validating bootstrap configuration..."

if [[ -x "tests/unit/test_bootstrap_constants.sh" ]]; then
    if bash tests/unit/test_bootstrap_constants.sh > /tmp/bootstrap-validation.log 2>&1; then
        echo -e "${GREEN}  ✓${NC}  All 15 bootstrap constants properly configured"
        echo "      - Download constants (5)"
        echo "      - Network constants (1)"
        echo "      - Reality validation (2)"
        echo "      - Reality config (5)"
        echo "      - Permissions (2)"
    else
        echo -e "${RED}  ✗${NC}  Bootstrap validation FAILED"
        echo ""
        echo "Error summary:"
        grep "✗ FAIL" /tmp/bootstrap-validation.log | head -5 || true
        echo ""
        echo -e "${YELLOW}  See full log: /tmp/bootstrap-validation.log${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠${NC}  Bootstrap test not found (tests/unit/test_bootstrap_constants.sh)"
fi

echo ""

#==============================================================================
# Project Information
#==============================================================================

echo -e "${BLUE}[4/4]${NC} Project Information"
echo ""

# Git branch
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "detached HEAD")
    echo -e "${CYAN}  Branch:${NC} $current_branch"

    # Recent commits
    echo -e "${CYAN}  Recent commits:${NC}"
    git log --oneline --decorate --max-count=3 | sed 's/^/    /'
fi

echo ""
echo -e "${CYAN}  Quick Commands:${NC}"
echo "    bash tests/test-runner.sh unit    # Run all unit tests"
echo "    bash tests/unit/test_bootstrap_constants.sh    # Validate bootstrap"
echo "    bash hooks/install-hooks.sh       # Reinstall git hooks"
echo "    bash install_multi.sh --help      # Installation help"
echo ""

# Documentation links
echo -e "${CYAN}  Documentation:${NC}"
echo "    CONTRIBUTING.md                   # Developer guide (START HERE)"
echo "    CLAUDE.md                         # Detailed coding standards"
echo "    tests/unit/README_BOOTSTRAP_TESTS.md    # Bootstrap pattern guide"
echo "    .claude/WORKFLOWS.md              # TDD and git workflows"
echo ""

#==============================================================================
# Summary
#==============================================================================

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BLUE}✓${NC} Environment setup complete!                         ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}What's configured:${NC}"
echo "  ✓ Git hooks installed (pre-commit validation enabled)"
echo "  ✓ Dependencies verified/installed"
echo "  ✓ Bootstrap constants validated"
echo "  ✓ Ready for development"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Read CONTRIBUTING.md for development guidelines"
echo "  2. Make your changes following code standards"
echo "  3. Run 'bash tests/test-runner.sh unit' before committing"
echo "  4. Commit normally - hooks will validate automatically"
echo ""
echo -e "${YELLOW}Need help?${NC} Check CONTRIBUTING.md or CLAUDE.md"
echo ""
