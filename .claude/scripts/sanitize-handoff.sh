#!/usr/bin/env bash
set -euo pipefail

# Handoff Sanitization Script
# Removes sensitive data from handoff files before committing to git
# Usage: bash .claude/scripts/sanitize-handoff.sh <filename> [--in-place]

# ============================================================================
# Configuration
# ============================================================================

readonly HANDOFFS_DIR=".claude/handoffs"

# Regex patterns for sensitive data
readonly UUID_PATTERN='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
readonly IPV4_PATTERN='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
readonly IPV6_PATTERN='([0-9a-f]{1,4}:){7}[0-9a-f]{1,4}'
readonly PRIVATE_KEY_PATTERN='[A-Za-z0-9+/]{40,}={0,2}'
readonly BASE64_TOKEN_PATTERN='[A-Za-z0-9+/]{32,}={0,2}'

# Replacement strings
readonly UUID_REPLACEMENT='UUID_PLACEHOLDER'
readonly IPV4_REPLACEMENT='SERVER_IP'
readonly IPV6_REPLACEMENT='SERVER_IPV6'
readonly PRIVATE_KEY_REPLACEMENT='PRIVATE_KEY_REDACTED'
readonly TOKEN_REPLACEMENT='TOKEN_REDACTED'
readonly PASSWORD_REPLACEMENT='PASSWORD_REDACTED'

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

# ============================================================================
# Sanitization Functions
# ============================================================================

sanitize_uuids() {
    local content="$1"
    echo "$content" | sed -E "s/${UUID_PATTERN}/${UUID_REPLACEMENT}/g"
}

sanitize_ipv4() {
    local content="$1"
    # Exclude common non-IP patterns (version numbers, dates)
    echo "$content" | sed -E "s/\b${IPV4_PATTERN}\b/${IPV4_REPLACEMENT}/g" | \
        sed -E "s/${IPV4_REPLACEMENT}\.0/${IPV4_PATTERN}.0/g" | \
        sed -E "s/1\.2\.3\.4/${IPV4_REPLACEMENT}/g"
}

sanitize_ipv6() {
    local content="$1"
    echo "$content" | sed -E "s/${IPV6_PATTERN}/${IPV6_REPLACEMENT}/g"
}

sanitize_private_keys() {
    local content="$1"
    # Look for context clues: "private_key", "privateKey", "key:"
    echo "$content" | sed -E "s/(private[_-]?key[\"']?:\s*[\"']?)${PRIVATE_KEY_PATTERN}([\"']?)/\1${PRIVATE_KEY_REPLACEMENT}\2/gi" | \
        sed -E "s/(Private[_ ]?[Kk]ey:\s*)${PRIVATE_KEY_PATTERN}/\1${PRIVATE_KEY_REPLACEMENT}/g"
}

sanitize_tokens() {
    local content="$1"
    # Look for: "token", "api_key", "secret"
    echo "$content" | sed -E "s/(token[\"']?:\s*[\"']?)${BASE64_TOKEN_PATTERN}([\"']?)/\1${TOKEN_REPLACEMENT}\2/gi" | \
        sed -E "s/(api[_-]?key[\"']?:\s*[\"']?)${BASE64_TOKEN_PATTERN}([\"']?)/\1${TOKEN_REPLACEMENT}\2/gi" | \
        sed -E "s/(secret[\"']?:\s*[\"']?)${BASE64_TOKEN_PATTERN}([\"']?)/\1${TOKEN_REPLACEMENT}\2/gi"
}

sanitize_passwords() {
    local content="$1"
    # Look for: "password", "passwd", "pwd"
    echo "$content" | sed -E "s/(password[\"']?:\s*[\"']?)[^\"'\s]+([\"']?)/\1${PASSWORD_REPLACEMENT}\2/gi" | \
        sed -E "s/(passwd[\"']?:\s*[\"']?)[^\"'\s]+([\"']?)/\1${PASSWORD_REPLACEMENT}\2/gi" | \
        sed -E "s/(pwd[\"']?:\s*[\"']?)[^\"'\s]+([\"']?)/\1${PASSWORD_REPLACEMENT}\2/gi"
}

# Sanitize all patterns
sanitize_content() {
    local content="$1"

    content=$(sanitize_uuids "$content")
    content=$(sanitize_ipv4 "$content")
    content=$(sanitize_ipv6 "$content")
    content=$(sanitize_private_keys "$content")
    content=$(sanitize_tokens "$content")
    content=$(sanitize_passwords "$content")

    echo "$content"
}

# ============================================================================
# Main Sanitization Logic
# ============================================================================

sanitize_file() {
    local input_file="$1"
    local in_place="${2:-false}"

    [[ ! -f "$input_file" ]] && die "File not found: $input_file"

    log_info "Sanitizing: $input_file"

    # Read original content
    local original_content
    original_content=$(cat "$input_file")

    # Sanitize
    local sanitized_content
    sanitized_content=$(sanitize_content "$original_content")

    # Check if anything changed
    if [[ "$original_content" == "$sanitized_content" ]]; then
        log_success "No sensitive data found - file is clean"
        return 0
    fi

    # Determine output file
    local output_file
    if [[ "$in_place" == "true" ]]; then
        output_file="$input_file"
    else
        output_file="${input_file%.md}.sanitized.md"
    fi

    # Write sanitized content
    echo "$sanitized_content" > "$output_file"

    # Show summary
    local changes
    changes=$(diff -u <(echo "$original_content") <(echo "$sanitized_content") | grep -E "^[-+]" | grep -v "^[-+]{3}" | wc -l)

    log_success "Sanitized successfully"
    log_info "Changes: $changes line(s)"

    if [[ "$in_place" == "true" ]]; then
        log_info "Updated: $output_file"
    else
        log_info "Created: $output_file"
        log_info "Review changes: diff -u $input_file $output_file"
    fi

    # Show diff preview
    echo ""
    echo "Preview of changes:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    diff -u <(echo "$original_content") <(echo "$sanitized_content") | head -n 30 || true
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$in_place" != "true" ]]; then
        log_warning "Original file unchanged. Use --in-place to modify directly."
    fi
}

# ============================================================================
# Batch Sanitization
# ============================================================================

sanitize_all() {
    local in_place="${1:-false}"

    [[ ! -d "$HANDOFFS_DIR" ]] && die "Handoffs directory not found: $HANDOFFS_DIR"

    local count=0

    log_info "Sanitizing all handoffs in: $HANDOFFS_DIR"
    echo ""

    for file in "${HANDOFFS_DIR}"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "README.md" ]] && continue

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sanitize_file "$file" "$in_place"
        ((count++))
        echo ""
    done

    log_success "Processed $count handoff(s)"
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Handoff Sanitization Script

Removes sensitive data from handoff files before committing to git.

Usage: bash .claude/scripts/sanitize-handoff.sh <filename> [options]
       bash .claude/scripts/sanitize-handoff.sh --all [options]

Options:
  --in-place              Modify file in place (default: create .sanitized.md)
  --all                   Sanitize all handoffs in directory

What gets sanitized:
  • UUIDs → UUID_PLACEHOLDER
  • IPv4 addresses → SERVER_IP
  • IPv6 addresses → SERVER_IPV6
  • Private keys → PRIVATE_KEY_REDACTED
  • API tokens → TOKEN_REDACTED
  • Passwords → PASSWORD_REDACTED

Examples:
  # Create sanitized copy
  bash .claude/scripts/sanitize-handoff.sh 2025-11-22-feature.md

  # Sanitize in place
  bash .claude/scripts/sanitize-handoff.sh 2025-11-22-feature.md --in-place

  # Sanitize all handoffs
  bash .claude/scripts/sanitize-handoff.sh --all

  # Sanitize all in place
  bash .claude/scripts/sanitize-handoff.sh --all --in-place

After sanitization:
  1. Review changes: diff -u original.md original.sanitized.md
  2. Verify no sensitive data remains
  3. Commit: git add .claude/handoffs/original.sanitized.md

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    local in_place=false
    local all=false
    local filename=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --in-place)
                in_place=true
                shift
                ;;
            --all)
                all=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                filename="$1"
                shift
                ;;
        esac
    done

    if $all; then
        sanitize_all "$in_place"
    elif [[ -n "$filename" ]]; then
        # If filename doesn't have full path, assume it's in handoffs dir
        if [[ ! -f "$filename" ]] && [[ -f "${HANDOFFS_DIR}/${filename}" ]]; then
            filename="${HANDOFFS_DIR}/${filename}"
        fi

        sanitize_file "$filename" "$in_place"
    else
        die "No filename provided. Use --all to sanitize all handoffs."
    fi
}

main "$@"
