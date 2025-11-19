#!/usr/bin/env bash
# .claude/scripts/lint-shell.sh
# PostToolUse hook for automatic shell script linting
#
# This hook runs after Edit/Write operations on shell scripts and:
# 1. Lints bash files with ShellCheck (if available)
# 2. Provides helpful feedback when ShellCheck is missing
# 3. Only processes .sh files and install_multi.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Read hook input from stdin
INPUT=$(cat)

# Extract file path from hook input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Exit early if no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only process shell script files
if [[ ! "$FILE_PATH" =~ \.(sh)$ ]] && [[ ! "$FILE_PATH" == "install_multi.sh" ]]; then
    exit 0
fi

# Exit early if file doesn't exist (might be deleted)
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

#==============================================================================
# Check if ShellCheck is available
#==============================================================================
if ! command -v shellcheck >/dev/null 2>&1; then
    # Provide helpful installation instructions
    cat >&2 <<'EOF'
┌─────────────────────────────────────────────────────────────┐
│ ⚠️  ShellCheck Not Installed                                │
├─────────────────────────────────────────────────────────────┤
│ Install ShellCheck for automatic shell script linting:      │
│                                                              │
│   Debian/Ubuntu:  sudo apt install shellcheck               │
│   macOS:          brew install shellcheck                   │
│   Snap:           sudo snap install shellcheck              │
│   Go:             go install github.com/koalaman/shellcheck │
│                                                              │
│ Your code will be validated in pre-commit and CI/CD.        │
└─────────────────────────────────────────────────────────────┘
EOF
    # Non-blocking warning (exit code 1, not 2)
    exit 1
fi

#==============================================================================
# Lint the shell script with ShellCheck
#==============================================================================

# ShellCheck configuration (matching pre-commit hook)
# -S warning: Show warnings and above (not just errors)
# -e SC2250: Exclude preference for explicit over implicit arithmetic
# This matches hooks/pre-commit configuration for consistency

# Capture ShellCheck output
LINT_OUTPUT=$(shellcheck -S warning -e SC2250 "$FILE_PATH" 2>&1 || true)

# Check if there are any issues
if [[ -z "$LINT_OUTPUT" ]]; then
    # File is clean
    echo -e "${GREEN}✓${NC} ShellCheck passed: $(basename "$FILE_PATH")" >&2

    # Return JSON to suppress output in transcript
    cat <<'EOF'
{
  "suppressOutput": true,
  "systemMessage": "Shell script passed ShellCheck validation"
}
EOF
    exit 0
fi

#==============================================================================
# Format and display ShellCheck issues
#==============================================================================

# Count issues
ISSUE_COUNT=$(echo "$LINT_OUTPUT" | grep -c "^In.*line" || echo "0")

# Display formatted output
echo -e "${YELLOW}⚠${NC} ShellCheck found ${ISSUE_COUNT} issue(s) in $(basename "$FILE_PATH"):" >&2
echo "" >&2

# Show the actual ShellCheck output with nice formatting
echo "$LINT_OUTPUT" | while IFS= read -r line; do
    if [[ "$line" =~ ^In.*line ]]; then
        # Line reference (e.g., "In file.sh line 45:")
        echo -e "  ${BLUE}$line${NC}" >&2
    elif [[ "$line" =~ ^SC[0-9]+ ]]; then
        # ShellCheck code (e.g., "SC2086: ...")
        echo -e "  ${YELLOW}$line${NC}" >&2
    else
        # Other lines (code snippets, suggestions)
        echo "  $line" >&2
    fi
done

echo "" >&2
echo -e "${BLUE}ℹ${NC} To see details, run: ${BLUE}shellcheck $(basename "$FILE_PATH")${NC}" >&2
echo -e "${BLUE}ℹ${NC} To disable specific warnings, add: ${BLUE}# shellcheck disable=SC####${NC}" >&2
echo "" >&2

# Non-blocking warning (exit code 1, not 2)
# This allows development to continue while showing issues
exit 1
