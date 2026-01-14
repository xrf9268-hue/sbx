#!/usr/bin/env bash
# lib/colors.sh - Terminal color definitions
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Provides color constants for terminal output
# Dependencies: None (foundation module)
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_COLORS_LOADED:-}" ]] && return 0
readonly _SBX_COLORS_LOADED=1

#==============================================================================
# Terminal Color Initialization
#==============================================================================

# Initialize terminal colors using tput
# Sets up the following color variables:
#   B      - Bold
#   N      - Normal/Reset
#   R      - Red
#   G      - Green
#   Y      - Yellow
#   BLUE   - Blue
#   PURPLE - Purple
#   CYAN   - Cyan
#
# If terminal doesn't support colors, variables are set to empty strings
_init_colors() {
  # Check if tput is available and terminal supports colors
  # Also handle cases where TERM is unset or set to 'unknown'
  local term_type="${TERM:-dumb}"
  if [[ "${term_type}" != "dumb" && "${term_type}" != "unknown" ]] \
    && command -v tput > /dev/null 2>&1 \
    && tput colors > /dev/null 2>&1; then
    # Terminal supports colors
    B="$(tput bold)"
    N="$(tput sgr0)"
    R="$(tput setaf 1)"
    G="$(tput setaf 2)"
    Y="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    PURPLE="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
  else
    # No color support - use empty strings
    B="" N="" R="" G="" Y="" BLUE="" PURPLE="" CYAN=""
  fi

  # Export for use in other modules
  export B N R G Y BLUE PURPLE CYAN
  readonly B N R G Y BLUE PURPLE CYAN
}

# Initialize colors immediately
_init_colors

#==============================================================================
# Export Functions
#==============================================================================

# Note: Colors are exported by _init_colors() function
# No additional exports needed
