#!/usr/bin/env bash
# .claude/scripts/format-and-lint-shell.sh
# PostToolUse hook for sequential shell script formatting and linting
#
# This hook runs after Edit/Write operations on shell scripts and:
# 1. Formats bash files with shfmt (if available)
# 2. Then lints the formatted result with ShellCheck (if available)
# 3. Ensures proper execution order to avoid race conditions
#
# IMPORTANT: This script runs format THEN lint sequentially to avoid:
# - Race conditions on stdin consumption
# - Race conditions on file modification
# - Linting unformatted code

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if jq is available (required to parse hook input)
if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<'EOF'
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  jq Not Installed (Required for Claude Hooks)            │
├─────────────────────────────────────────────────────────────┤
│ Install jq to enable automatic shell script hooks:          │
│                                                              │
│   Debian/Ubuntu:  sudo apt install jq                       │
│   macOS:          brew install jq                           │
│                                                              │
│ The SessionStart hook normally installs this automatically. │
└─────────────────────────────────────────────────────────────┘
EOF
  exit 1
fi

# Read hook input from stdin ONCE (critical for parallel execution)
INPUT=$(cat)

# Extract file path from hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Exit early if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only process shell script files
if [[ ! "$FILE_PATH" =~ \.(sh)$ ]] && [[ ! "$FILE_PATH" != "install_multi.sh" ]]; then
    exit 0
fi

# Exit early if file doesn't exist (might be deleted)
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

#==============================================================================
# STEP 1: Format the shell script with shfmt
#==============================================================================

FORMATTED=false
SHFMT_AVAILABLE=false

if command -v shfmt >/dev/null 2>&1; then
    SHFMT_AVAILABLE=true

    # Check if file needs formatting (dry-run)
    if shfmt -d -i 2 -bn -ci -sr -kp "$FILE_PATH" >/dev/null 2>&1; then
        # File is already formatted
        echo -e "${GREEN}✓${NC} Shell script already formatted: $(basename "$FILE_PATH")" >&2
    else
        # Format the file in-place
        if shfmt -w -i 2 -bn -ci -sr -kp "$FILE_PATH" 2>/dev/null; then
            echo -e "${BLUE}✓${NC} Auto-formatted shell script: $(basename "$FILE_PATH")" >&2
            FORMATTED=true
        else
            # Formatting failed - likely syntax error
            echo -e "${RED}✗${NC} Failed to format \"$FILE_PATH\" - syntax error?" >&2
            echo "  Run: shfmt -d \"$FILE_PATH\"" >&2
            # Don't exit - continue to linting for more detailed error messages
        fi
    fi
else
    # shfmt not available - show warning once
    cat >&2 <<'EOF'
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  Shell Formatter Not Installed                           │
├─────────────────────────────────────────────────────────────┤
│ Install shfmt for automatic shell script formatting:        │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shfmt                    │
│   macOS:          brew install shfmt                        │
│   Go:             go install mvdan.cc/sh/v3/cmd/shfmt@latest│
│                                                              │
│ Your code is valid but not auto-formatted.                  │
└─────────────────────────────────────────────────────────────┘
EOF
fi

#==============================================================================
# STEP 2: Lint the shell script with ShellCheck
# This runs AFTER formatting to lint the formatted result
#==============================================================================

SHELLCHECK_AVAILABLE=false
LINT_PASSED=false

if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_AVAILABLE=true

    # Capture ShellCheck output
    LINT_OUTPUT=$(shellcheck -S warning -e SC2250 "$FILE_PATH" 2>&1 || true)

    # Check if there are any issues
    if [[ -z "$LINT_OUTPUT" ]]; then
        # File is clean
        echo -e "${GREEN}✓${NC} ShellCheck passed: $(basename "$FILE_PATH")" >&2
        LINT_PASSED=true
    else
        # Count issues
        ISSUE_COUNT=$(echo "$LINT_OUTPUT" | grep -c "^In.*line" || echo "0")

        # Display formatted output
        echo -e "${YELLOW}⚠${NC} ShellCheck found ${ISSUE_COUNT} issue(s) in $(basename "$FILE_PATH"):" >&2
        echo "" >&2

        # Show the actual ShellCheck output with nice formatting
        echo "$LINT_OUTPUT" | while IFS= read -r line; do
            if [[ "$line" =~ ^In.*line ]]; then
                # Line reference
                echo -e "  ${BLUE}$line${NC}" >&2
            elif [[ "$line" =~ ^SC[0-9]+ ]]; then
                # ShellCheck code
                echo -e "  ${YELLOW}$line${NC}" >&2
            else
                # Other lines
                echo "  $line" >&2
            fi
        done

        echo "" >&2
        echo -e "${BLUE}ℹ${NC} To see details, run: ${BLUE}shellcheck \"$FILE_PATH\"${NC}" >&2
        echo -e "${BLUE}ℹ${NC} To disable specific warnings, add: ${BLUE}# shellcheck disable=SC####${NC}" >&2
        echo "" >&2
    fi
else
    # ShellCheck not available - show warning once
    cat >&2 <<'EOF'
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  ShellCheck Not Installed                                │
├─────────────────────────────────────────────────────────────┤
│ Install ShellCheck for automatic shell script linting:      │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shellcheck               │
│   macOS:          brew install shellcheck                   │
│   Snap:           sudo snap install shellcheck              │
│                                                              │
│ Your code will be validated in pre-commit and CI/CD.        │
└─────────────────────────────────────────────────────────────┘
EOF
fi

#==============================================================================
# Return appropriate exit code and JSON output
#==============================================================================

# If both tools passed or are unavailable, suppress output
if [[ "$LINT_PASSED" == "true" ]] || [[ "$SHELLCHECK_AVAILABLE" == "false" ]]; then
    cat <<EOF
{
  "suppressOutput": true,
  "systemMessage": "Shell script processed: formatted=${FORMATTED}, lint_passed=${LINT_PASSED}"
}
EOF
    exit 0
fi

# If linting found issues, exit with non-blocking code 1
# This allows development to continue while showing issues
exit 1
