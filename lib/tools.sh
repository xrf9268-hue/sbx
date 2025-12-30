#!/usr/bin/env bash
# lib/tools.sh - External tool abstractions and wrappers
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Provides abstraction layer for external tools with fallback mechanisms
# Dependencies: lib/common.sh
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_TOOLS_LOADED:-}" ]] && return 0
readonly _SBX_TOOLS_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"

#==============================================================================
# JSON Operations
#==============================================================================

# Parse JSON with fallback to Python
#
# Usage: json_parse <json_string> <jq_filter>
# Example: json_parse '{"name":"test"}' '.name'
#
# Returns: Extracted value or error
# Exit code: 0 on success, 1 on failure
json_parse() {
    local json_input="$1"
    shift
    local jq_filter="$*"

    # Primary: Use jq if available
    if have jq; then
        echo "$json_input" | jq -r "$jq_filter" 2>/dev/null && return 0
    fi

    # Fallback 1: Python 3
    if have python3; then
        python3 -c "
import json
import sys
try:
    data = json.loads('''$json_input''')
    # Basic jq filter support for simple cases
    filter = '$jq_filter'
    if filter.startswith('.'):
        key = filter[1:]
        if '[' in key:
            # Handle array access like .items[0]
            key_parts = key.replace('[', '.').replace(']', '').split('.')
            result = data
            for part in key_parts:
                if part:
                    result = result[int(part)] if part.isdigit() else result[part]
            print(result)
        else:
            print(data.get(key, ''))
    else:
        print(json.dumps(data))
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && return 0
    fi

    # Fallback 2: Python 2 (legacy)
    if have python; then
        python -c "
import json
import sys
try:
    data = json.loads('''$json_input''')
    filter = '$jq_filter'
    if filter.startswith('.'):
        key = filter[1:]
        print(data.get(key, ''))
    else:
        print(json.dumps(data))
except Exception as e:
    print >> sys.stderr, 'Error:', e
    sys.exit(1)
" 2>/dev/null && return 0
    fi

    # No parser available
    err "No JSON parser available (jq, python3, python)"
    return 1
}

# Build JSON object using jq
#
# Usage: json_build [jq_args...] <jq_expression>
# Example: json_build --arg name "test" '{name: $name}'
#
# Returns: JSON string
# Exit code: 0 on success, 1 on failure
json_build() {
    if have jq; then
        jq -n "$@" 2>/dev/null || {
            err "JSON build failed"
            return 1
        }
    else
        err "JSON builder requires jq"
        return 1
    fi
}

# Validate JSON file syntax
#
# Usage: validate_json_syntax <json_file> [verbose]
# Example: validate_json_syntax /path/to/config.json
#          validate_json_syntax /path/to/config.json verbose
#
# Args:
#   $1 - Path to JSON file
#   $2 - (optional) "verbose" for detailed error messages
#
# Returns: 0 if valid, 1 if invalid
# Output: Error messages if verbose mode or validation fails
#
# Features:
#   - Checks file exists and is readable
#   - Validates file is not empty (contains non-whitespace)
#   - Validates JSON syntax using jq (preferred) or python fallback
#   - Supports python3 and python2 for maximum compatibility
#   - Verbose mode provides detailed error context
#
# Note: This is the authoritative implementation. Previously duplicated in
#       lib/config_validator.sh and lib/validation.sh (now removed).
validate_json_syntax() {
    local json_file="$1"
    local verbose="${2:-}"

    # Check file exists
    if [[ ! -f "$json_file" ]]; then
        [[ "$verbose" == "verbose" ]] && err "JSON file not found: $json_file"
        return 1
    fi

    # Check file is readable
    if [[ ! -r "$json_file" ]]; then
        [[ "$verbose" == "verbose" ]] && err "JSON file not readable: $json_file"
        return 1
    fi

    # Check file is not empty and contains non-whitespace content
    if [[ ! -s "$json_file" ]] || ! grep -q '[^[:space:]]' "$json_file" 2>/dev/null; then
        [[ "$verbose" == "verbose" ]] && err "JSON file is empty: $json_file"
        return 1
    fi

    # Primary: Validate with jq
    if have jq; then
        if jq empty < "$json_file" 2>/dev/null; then
            return 0
        else
            [[ "$verbose" == "verbose" ]] && err "Invalid JSON syntax in: $json_file"
            return 1
        fi
    fi

    # Fallback 1: Python 3
    if have python3; then
        if python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
            return 0
        else
            [[ "$verbose" == "verbose" ]] && err "Invalid JSON syntax in: $json_file"
            return 1
        fi
    fi

    # Fallback 2: Python 2 (for legacy systems)
    if have python; then
        if python -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
            return 0
        else
            [[ "$verbose" == "verbose" ]] && err "Invalid JSON syntax in: $json_file"
            return 1
        fi
    fi

    # No validation tools available - warn and assume valid
    # This prevents installation failures on minimal systems
    if [[ "$verbose" == "verbose" ]]; then
        warn "No JSON validation tools available (jq, python3, python)"
        warn "Skipping syntax validation for: $json_file"
    fi
    return 0
}

#==============================================================================
# Cryptographic Operations
#==============================================================================

# Generate random bytes (hex encoded)
#
# Usage: crypto_random_hex <length>
# Example: crypto_random_hex 16  # Generates 32 hex chars (16 bytes)
#
# Returns: Hex string
# Exit code: 0 on success, 1 on failure
crypto_random_hex() {
    local length="${1:-16}"

    # Primary: Use openssl
    if have openssl; then
        openssl rand -hex "$length" 2>/dev/null && return 0
    fi

    # Fallback: Use /dev/urandom with xxd
    if [[ -f /dev/urandom ]] && have xxd; then
        head -c "$length" /dev/urandom 2>/dev/null | xxd -p -c "$length" | tr -d '\n' && return 0
    fi

    # Fallback: Use /dev/urandom with od
    if [[ -f /dev/urandom ]] && have od; then
        head -c "$length" /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' && return 0
    fi

    # No random source available
    err "No random source available (openssl, /dev/urandom with xxd/od)"
    return 1
}

# Calculate SHA256 checksum
#
# Usage: crypto_sha256 <file>
# Example: crypto_sha256 /path/to/file
#
# Returns: SHA256 hex string (lowercase)
# Exit code: 0 on success, 1 on failure
crypto_sha256() {
    local file="$1"

    # Validate file exists
    [[ -f "$file" ]] || {
        err "File not found: $file"
        return 1
    }

    local checksum=""

    # Primary: Use sha256sum (Linux)
    if have sha256sum; then
        checksum=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
        [[ -n "$checksum" ]] && echo "$checksum" && return 0
    fi

    # Fallback 1: Use shasum (macOS/BSD)
    if have shasum; then
        checksum=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
        [[ -n "$checksum" ]] && echo "$checksum" && return 0
    fi

    # Fallback 2: Use openssl
    if have openssl; then
        checksum=$(openssl sha256 "$file" 2>/dev/null | awk '{print $2}')
        [[ -n "$checksum" ]] && echo "$checksum" && return 0
    fi

    # No SHA256 tool available
    err "No SHA256 tool available (sha256sum, shasum, openssl)"
    return 1
}

#==============================================================================
# HTTP Operations
#==============================================================================

# Download file with fallback
#
# Usage: http_download <url> <output_file> [timeout_seconds]
# Example: http_download "https://example.com/file" "/tmp/file" 30
#
# Returns: Downloaded file at output path
# Exit code: 0 on success, 1 on failure
http_download() {
    local url="$1"
    local output="$2"
    local timeout="${3:-${HTTP_TIMEOUT_SEC:-30}}"

    # Validate URL format
    if [[ ! "$url" =~ ^https?:// ]]; then
        err "Invalid URL format: $url"
        return 1
    fi

    # Primary: Use curl
    if have curl; then
        curl -fsSL \
            --connect-timeout 10 \
            --max-time "$timeout" \
            --retry 2 \
            --retry-delay 1 \
            "$url" -o "$output" 2>/dev/null && return 0
    fi

    # Fallback: Use wget
    if have wget; then
        wget -q \
            --timeout="$timeout" \
            --tries=2 \
            --waitretry=1 \
            "$url" -O "$output" 2>/dev/null && return 0
    fi

    # No HTTP client available
    err "No HTTP client available (curl, wget)"
    return 1
}

# Fetch URL content to stdout
#
# Usage: http_fetch <url> [timeout_seconds]
# Example: http_fetch "https://api.ipify.org" 5
#
# Returns: Content to stdout
# Exit code: 0 on success, 1 on failure
http_fetch() {
    local url="$1"
    local timeout="${2:-${HTTP_TIMEOUT_SEC:-30}}"

    # Validate URL format
    if [[ ! "$url" =~ ^https?:// ]]; then
        err "Invalid URL format: $url"
        return 1
    fi

    # Primary: Use curl
    if have curl; then
        curl -fsSL \
            --connect-timeout 10 \
            --max-time "$timeout" \
            "$url" 2>/dev/null && return 0
    fi

    # Fallback: Use wget
    if have wget; then
        wget -qO- \
            --timeout="$timeout" \
            "$url" 2>/dev/null && return 0
    fi

    # No HTTP client available
    err "No HTTP client available (curl, wget)"
    return 1
}

#==============================================================================
# Encoding Operations
#==============================================================================

# Base64 encode
#
# Usage: base64_encode <string>
#        echo "string" | base64_encode
# Example: base64_encode "hello world"
#
# Returns: Base64 encoded string
# Exit code: 0 on success, 1 on failure
base64_encode() {
    local input="${1:-}"

    # Read from stdin if no argument provided
    if [[ -z "$input" ]]; then
        if have base64; then
            base64 2>/dev/null && return 0
        fi
        if have openssl; then
            openssl base64 2>/dev/null && return 0
        fi
    else
        # Use argument
        if have base64; then
            echo -n "$input" | base64 2>/dev/null && return 0
        fi
        if have openssl; then
            echo -n "$input" | openssl base64 2>/dev/null && return 0
        fi
    fi

    err "No base64 encoder available"
    return 1
}

# Base64 decode
#
# Usage: base64_decode <base64_string>
#        echo "base64_string" | base64_decode
# Example: base64_decode "aGVsbG8gd29ybGQ="
#
# Returns: Decoded string
# Exit code: 0 on success, 1 on failure
base64_decode() {
    local input="${1:-}"

    # Read from stdin if no argument provided
    if [[ -z "$input" ]]; then
        if have base64; then
            base64 -d 2>/dev/null && return 0
        fi
        if have openssl; then
            openssl base64 -d 2>/dev/null && return 0
        fi
    else
        # Use argument
        if have base64; then
            echo -n "$input" | base64 -d 2>/dev/null && return 0
        fi
        if have openssl; then
            echo -n "$input" | openssl base64 -d 2>/dev/null && return 0
        fi
    fi

    err "No base64 decoder available"
    return 1
}

#==============================================================================
# Export Functions
#==============================================================================

export -f json_parse json_build
export -f crypto_random_hex crypto_sha256
export -f http_download http_fetch
export -f base64_encode base64_decode
