#!/usr/bin/env bash
# .claude/scripts/format-and-lint-shell.sh
# PostToolUse hook for sequential shell script formatting and linting
#
# Optimized for minimal output while maintaining full functionality.
# Runs format → lint sequentially to avoid race conditions.

set -euo pipefail

# Check if jq is available (required to parse hook input)
if ! command -v jq > /dev/null 2>&1; then
  echo "ERROR: jq required for hooks. Install: apt install jq (or brew install jq)" >&2
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

# Only process shell script files (.sh extension or specific known scripts)
if [[ ! "$FILE_PATH" =~ \.sh$ ]] && [[ "$(basename "$FILE_PATH")" != "install.sh" ]]; then
  exit 0
fi

# Exit early if file doesn't exist (might be deleted)
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

#==============================================================================
# STEP 1: Format with shfmt (if available)
#==============================================================================

FORMATTED=false
SHFMT_AVAILABLE=false
SHFMT_WARNING_FILE="/tmp/sbx-shfmt-warning-shown"

if command -v shfmt > /dev/null 2>&1; then
  SHFMT_AVAILABLE=true

  # Check if file needs formatting (dry-run)
  if ! shfmt -d -i 2 -bn -ci -sr "$FILE_PATH" > /dev/null 2>&1; then
    # Format the file in-place
    if shfmt -w -i 2 -bn -ci -sr "$FILE_PATH" 2> /dev/null; then
      echo "✓ Formatted: $(basename "$FILE_PATH")" >&2
      FORMATTED=true
    else
      # Formatting failed - likely syntax error
      echo "✗ Format failed: $FILE_PATH (run: shfmt -d \"$FILE_PATH\")" >&2
    fi
  fi
else
  # Show warning only once per session (avoid spam)
  if [[ ! -f "$SHFMT_WARNING_FILE" ]]; then
    echo "⚠ shfmt not installed. Install: snap install shfmt (or go install mvdan.cc/sh/v3/cmd/shfmt@latest)" >&2
    touch "$SHFMT_WARNING_FILE"
  fi
fi

#==============================================================================
# STEP 2: Lint with ShellCheck (if available)
#==============================================================================

SHELLCHECK_AVAILABLE=false
LINT_PASSED=false
SHELLCHECK_WARNING_FILE="/tmp/sbx-shellcheck-warning-shown"

if command -v shellcheck > /dev/null 2>&1; then
  SHELLCHECK_AVAILABLE=true

  # Capture ShellCheck output
  LINT_OUTPUT=$(shellcheck -S warning -e SC2250 "$FILE_PATH" 2>&1 || true)

  if [[ -z "$LINT_OUTPUT" ]]; then
    # File is clean
    echo "✓ ShellCheck passed: $(basename "$FILE_PATH")" >&2
    LINT_PASSED=true
  else
    # Count and display issues concisely
    ISSUE_COUNT=$(echo "$LINT_OUTPUT" | grep -c "^In.*line" || echo "0")
    echo "⚠ ShellCheck found ${ISSUE_COUNT} issue(s) in $(basename "$FILE_PATH"):" >&2
    echo "$LINT_OUTPUT" | sed 's/^/  /' >&2
    echo "  → Run: shellcheck \"$FILE_PATH\"" >&2
    echo "  → Disable: # shellcheck disable=SC####" >&2
  fi
else
  # Show warning only once per session (avoid spam)
  if [[ ! -f "$SHELLCHECK_WARNING_FILE" ]]; then
    echo "⚠ shellcheck not installed. Install: apt install shellcheck (or brew/snap)" >&2
    touch "$SHELLCHECK_WARNING_FILE"
  fi
fi

#==============================================================================
# Return appropriate exit code and JSON output
#==============================================================================

# Suppress output in verbose mode when everything is clean
if [[ "$LINT_PASSED" == "true" ]] || [[ "$SHELLCHECK_AVAILABLE" == "false" ]]; then
  echo '{"suppressOutput": true}'
  exit 0
fi

# If linting found issues, exit with non-blocking code 1 (allows continued development)
exit 1
