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

# Extract fields from hook input (be tolerant of schema changes / invalid JSON)
FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT" 2>/dev/null || true)
SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null || true)

# Resolve a stable tmp dir and per-session marker suffix (avoid cross-project/session collisions)
TMP_DIR="${TMPDIR:-/tmp}"
SAFE_SESSION_ID=""
if [[ -n "$SESSION_ID" ]]; then
  SAFE_SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_.-' '_' || true)
fi
PROJECT_ID_BASENAME=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
SAFE_PROJECT_ID=$(printf '%s' "$PROJECT_ID_BASENAME" | tr -c 'A-Za-z0-9_.-' '_' || true)
MARKER_SUFFIX=""
if [[ -n "$SAFE_SESSION_ID" ]]; then
  MARKER_SUFFIX="-$SAFE_SESSION_ID"
fi

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
SHFMT_WARNING_FILE="${TMP_DIR}/sbx-${SAFE_PROJECT_ID}-shfmt-warning-shown${MARKER_SUFFIX}"

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
    echo "⚠ shfmt not installed. Install: brew install shfmt (macOS) or snap install shfmt (Linux) or go install mvdan.cc/sh/v3/cmd/shfmt@latest" >&2
    touch "$SHFMT_WARNING_FILE"
  fi
fi

#==============================================================================
# STEP 2: Lint with ShellCheck (if available)
#==============================================================================

SHELLCHECK_AVAILABLE=false
LINT_PASSED=false
SHELLCHECK_WARNING_FILE="${TMP_DIR}/sbx-${SAFE_PROJECT_ID}-shellcheck-warning-shown${MARKER_SUFFIX}"

if command -v shellcheck > /dev/null 2>&1; then
  SHELLCHECK_AVAILABLE=true

  # Prefer repo config when available (hook CWD is not guaranteed)
  SHELLCHECK_RCFILE=""
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && [[ -f "$CLAUDE_PROJECT_DIR/.shellcheckrc" ]]; then
    SHELLCHECK_RCFILE="$CLAUDE_PROJECT_DIR/.shellcheckrc"
  elif [[ -f ".shellcheckrc" ]]; then
    SHELLCHECK_RCFILE=".shellcheckrc"
  else
    REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$REPO_ROOT" ]] && [[ -f "$REPO_ROOT/.shellcheckrc" ]]; then
      SHELLCHECK_RCFILE="$REPO_ROOT/.shellcheckrc"
    fi
  fi

  # Capture ShellCheck output
  SHELLCHECK_ARGS=(--severity=warning --exclude=SC2250 --color=never)
  if [[ -n "$SHELLCHECK_RCFILE" ]]; then
    SHELLCHECK_ARGS=(--rcfile "$SHELLCHECK_RCFILE" "${SHELLCHECK_ARGS[@]}")
  fi
  LINT_OUTPUT=$(shellcheck "${SHELLCHECK_ARGS[@]}" "$FILE_PATH" 2>&1 || true)

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
