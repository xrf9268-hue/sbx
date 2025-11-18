#!/usr/bin/env bash
# hooks/install-hooks.sh - Install git hooks for sbx-lite development
#
# This script installs pre-commit hooks that enforce code quality standards
# and prevent common bugs (like unbound variable errors) from being committed.
#
# Usage:
#   bash hooks/install-hooks.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== sbx-lite Git Hooks Installer ===${NC}"
echo ""

# Get repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
SOURCE_HOOKS_DIR="$REPO_ROOT/hooks"

# Verify we're in a git repo
if [[ ! -d "$REPO_ROOT/.git" ]]; then
    echo -e "${RED}✗ ERROR${NC}: Not in a git repository"
    echo "  Please run this script from within the sbx-lite repository"
    exit 1
fi

# Verify hooks directory exists
if [[ ! -d "$SOURCE_HOOKS_DIR" ]]; then
    echo -e "${RED}✗ ERROR${NC}: hooks/ directory not found"
    echo "  Expected: $SOURCE_HOOKS_DIR"
    exit 1
fi

# Create .git/hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

#==============================================================================
# Install pre-commit hook
#==============================================================================
echo -e "${BLUE}[1/3]${NC} Installing pre-commit hook..."

if [[ -f "$HOOKS_DIR/pre-commit" ]]; then
    # Backup existing hook
    backup_file="$HOOKS_DIR/pre-commit.backup.$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}  ⚠${NC}  Existing pre-commit hook found"
    echo "      Backing up to: $(basename "$backup_file")"
    mv "$HOOKS_DIR/pre-commit" "$backup_file"
fi

# Install new hook
cp "$SOURCE_HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo -e "${GREEN}  ✓${NC}  Pre-commit hook installed"
echo ""

#==============================================================================
# Verify installation
#==============================================================================
echo -e "${BLUE}[2/3]${NC} Verifying installation..."

hooks_installed=0
hooks_failed=0

# Check pre-commit
if [[ -x "$HOOKS_DIR/pre-commit" ]]; then
    echo -e "${GREEN}  ✓${NC}  pre-commit hook is executable"
    hooks_installed=$((hooks_installed + 1))
else
    echo -e "${RED}  ✗${NC}  pre-commit hook is NOT executable"
    hooks_failed=$((hooks_failed + 1))
fi

echo ""

#==============================================================================
# Test hook functionality
#==============================================================================
echo -e "${BLUE}[3/3]${NC} Testing hook functionality..."

# Test that the hook can run
if bash "$HOOKS_DIR/pre-commit" --help >/dev/null 2>&1 || bash -n "$HOOKS_DIR/pre-commit" 2>/dev/null; then
    echo -e "${GREEN}  ✓${NC}  Pre-commit hook has valid syntax"
else
    echo -e "${RED}  ✗${NC}  Pre-commit hook has syntax errors"
    hooks_failed=$((hooks_failed + 1))
fi

echo ""

#==============================================================================
# Installation Summary
#==============================================================================
echo "========================================"
echo -e "${BLUE}Installation Summary${NC}"
echo "----------------------------------------"

if [[ $hooks_failed -eq 0 ]]; then
    echo -e "${GREEN}✓ Git hooks successfully installed!${NC}"
    echo ""
    echo "The following checks will run on every commit:"
    echo "  1. Bash syntax validation"
    echo "  2. Bootstrap constants validation"
    echo "  3. Strict mode enforcement (set -euo pipefail)"
    echo "  4. ShellCheck linting (if installed)"
    echo "  5. Unbound variable detection (bash -u)"
    echo ""
    echo -e "${YELLOW}What happens now:${NC}"
    echo "  • Every 'git commit' will run these checks automatically"
    echo "  • Commits will be blocked if checks fail"
    echo "  • You'll see clear error messages with remediation steps"
    echo ""
    echo -e "${YELLOW}Emergency bypass (use sparingly):${NC}"
    echo "  git commit --no-verify"
    echo ""
    echo -e "${GREEN}Recommendation:${NC}"
    echo "  Install ShellCheck for additional linting:"
    echo "    • Debian/Ubuntu: sudo apt install shellcheck"
    echo "    • macOS: brew install shellcheck"
    echo "    • RHEL/CentOS: sudo yum install ShellCheck"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Installation completed with errors${NC}"
    echo ""
    echo "  Hooks installed: $hooks_installed"
    echo "  Hooks failed: $hooks_failed"
    echo ""
    echo "Please review the errors above and try again."
    exit 1
fi
