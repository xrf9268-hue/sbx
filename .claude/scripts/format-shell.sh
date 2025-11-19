#!/usr/bin/env bash
# .claude/scripts/format-shell.sh
# PostToolUse hook for automatic shell script formatting
#
# This hook runs after Edit/Write operations on shell scripts and:
# 1. Formats bash files with shfmt (if available)
# 2. Provides helpful feedback when shfmt is missing
# 3. Only processes .sh files and install_multi.sh

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
# Check if shfmt is available
#==============================================================================
if ! command -v shfmt >/dev/null 2>&1; then
    # Provide helpful installation instructions
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
    # Non-blocking warning (exit code 1, not 2)
    exit 1
fi

#==============================================================================
# Format the shell script
#==============================================================================

# shfmt configuration (matching your project style)
# -i 2: 2-space indentation
# -bn: binary ops like && and | may start a line
# -ci: switch cases will be indented
# -sr: redirect operators will be followed by a space
# -kp: keep column alignment paddings

# Check if file needs formatting (dry-run)
if shfmt -d -i 2 -bn -ci -sr -kp "$FILE_PATH" >/dev/null 2>&1; then
    # File is already formatted
    echo -e "${GREEN}✓${NC} Shell script already formatted: $(basename "$FILE_PATH")" >&2
    exit 0
fi

# Format the file in-place
if shfmt -w -i 2 -bn -ci -sr -kp "$FILE_PATH" 2>/dev/null; then
    echo -e "${BLUE}✓${NC} Auto-formatted shell script: $(basename "$FILE_PATH")" >&2

    # Return JSON to indicate formatting occurred
    # (suppressOutput prevents cluttering transcript)
    cat <<'EOF'
{
  "suppressOutput": true,
  "systemMessage": "Shell script auto-formatted with shfmt"
}
EOF
    exit 0
else
    # Formatting failed - likely syntax error
    echo -e "${RED}✗${NC} Failed to format \"$FILE_PATH\" - syntax error?" >&2
    echo "  Run: shfmt -d \"$FILE_PATH\"" >&2
    # Non-blocking error
    exit 1
fi
