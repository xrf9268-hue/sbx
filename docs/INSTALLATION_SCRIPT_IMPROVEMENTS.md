# Installation Script Improvements

**Analysis Date:** 2025-11-18
**Reference:** Claude Code bootstrap.sh comparison

This document analyzes Claude's installation script and provides recommendations for improving sbx's install_multi.sh.

---

## Executive Summary

**What sbx does BETTER:**
- ✅ Progress indication and user feedback
- ✅ Comprehensive error handling and validation
- ✅ Modular architecture with library system
- ✅ Interactive menus and configuration options
- ✅ Retry logic with exponential backoff

**What sbx can LEARN:**
- 🎯 Make jq optional with pure bash fallback
- 🎯 Detect musl vs glibc for Alpine Linux support
- 🎯 Simplify bootstrapping dependencies
- 🎯 Cleaner download abstraction
- 🎯 More aggressive error exits

---

## Detailed Comparison

### 1. Dependency Management

#### Claude's Approach (Minimal Dependencies)
```bash
# Only requires curl OR wget - no jq, no other tools
if ! command -v curl >/dev/null && ! command -v wget >/dev/null; then
    echo "Error: curl or wget required"
    exit 1
fi

# Pure bash JSON parsing - no jq dependency
[[ $json =~ \"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]
```

**Pros:**
- Works on minimal systems (Alpine, busybox, embedded)
- Faster installation (no package manager calls)
- More reliable (fewer failure points)

**Cons:**
- Regex-based JSON parsing is fragile
- Limited to simple JSON structures

#### sbx Current Approach
```bash
# install_multi.sh:745
for tool in curl tar gzip jq openssl systemctl; do
    if ! have "$tool"; then
        missing+=("$tool")
    fi
done

# Installs missing tools automatically
apt-get install -y "${missing[@]}"  # or dnf/yum
```

**Pros:**
- Comprehensive validation
- Ensures all required tools available
- Good error messages

**Cons:**
- Requires package manager access
- Fails on minimal/locked-down systems
- jq installation can be slow

#### 🎯 Recommendation for sbx

**Option A: Make jq Optional (RECOMMENDED)**
```bash
ensure_tools() {
    local required=(curl tar gzip openssl systemctl)
    local optional=(jq)
    local missing=()
    local missing_optional=()

    for tool in "${required[@]}"; do
        if ! have "$tool"; then
            missing+=("$tool")
        fi
    done

    for tool in "${optional[@]}"; do
        if ! have "$tool"; then
            missing_optional+=("$tool")
        fi
    done

    # Install required tools
    if [[ ${#missing[@]} -gt 0 ]]; then
        msg "Installing required tools: ${missing[*]}"
        install_packages "${missing[@]}" || die "Failed to install required tools"
    fi

    # Warn about optional tools
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        warn "Optional tools not available: ${missing_optional[*]}"
        warn "Installation will use fallback methods (pure bash)"
    fi

    success "All required tools are available"
}
```

**Impact:**
- ✅ Works on more systems (Alpine, minimal containers)
- ✅ Faster installation when jq not present
- ✅ Still uses jq when available for robustness
- ⚠️ Requires lib/tools.sh to have robust pure bash fallbacks

**Option B: Keep Current Behavior (Simpler)**
- Keep installing jq as required
- Accept that minimal systems need manual jq installation
- Document the requirement clearly

**Recommendation:** Implement Option A. We already have `lib/tools.sh` with fallbacks, just need to stop treating jq as required.

---

### 2. Platform Detection (musl vs glibc)

#### Claude's Approach
```bash
# Detect musl libc on Linux (Alpine, embedded systems)
detect_libc() {
    # Method 1: Check for musl library
    if [ -f /lib/ld-musl-*.so.1 ]; then
        echo "musl"
        return
    fi

    # Method 2: Parse ldd output
    if ldd /bin/sh 2>/dev/null | grep -q musl; then
        echo "musl"
        return
    fi

    # Default to glibc
    echo "glibc"
}

# Use in platform detection
platform="linux-${arch}-$(detect_libc)"
```

**Why This Matters:**
- sing-box releases have separate binaries for musl and glibc
- Using wrong binary causes runtime errors or crashes
- Alpine Linux (popular for Docker) uses musl

#### sbx Current Approach
```bash
# install_multi.sh:559-578
detect_arch() {
    local arch detected_arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) detected_arch="amd64" ;;
        aarch64|arm64) detected_arch="arm64" ;;
        armv7l) detected_arch="armv7" ;;
        *) die "Unsupported architecture: $arch" ;;
    esac

    msg "Detected system architecture: $detected_arch (uname: $arch)"
    echo "$detected_arch"
}

# Download URL construction (install_multi.sh:779)
# Explicitly match linux-${arch}.tar.gz (no libc detection)
url=$(echo "$raw" | grep '"browser_download_url":' | grep -E "linux-${arch}\.tar\.gz\"")
```

**Problem:**
- ❌ No musl detection
- ❌ May download wrong binary on Alpine Linux
- ❌ sing-box releases include musl variants we don't use

#### 🎯 Recommendation for sbx

**Add libc Detection:**
```bash
# Add to install_multi.sh after detect_arch()

# Detect libc implementation (glibc vs musl)
detect_libc() {
    # Skip on non-Linux systems
    [[ "$(uname -s)" != "Linux" ]] && { echo ""; return; }

    # Method 1: Check for musl shared library
    if ls /lib/ld-musl-*.so.1 2>/dev/null | grep -q .; then
        echo "-musl"
        return
    fi

    # Method 2: Parse ldd output (more reliable)
    if command -v ldd >/dev/null 2>&1; then
        if ldd /bin/sh 2>/dev/null | grep -q musl; then
            echo "-musl"
            return
        fi
    fi

    # Method 3: Check /etc/os-release for Alpine
    if [[ -f /etc/os-release ]]; then
        if grep -qi "alpine" /etc/os-release; then
            echo "-musl"
            return
        fi
    fi

    # Default to glibc (or empty suffix for backward compatibility)
    echo ""
}

# Update download_singbox() to use libc detection
download_singbox() {
    # ... existing code ...

    local arch libc_suffix
    arch="$(detect_arch)"
    libc_suffix="$(detect_libc)"  # "-musl" or ""

    # Extract download URL with libc suffix
    # Example: linux-amd64-musl.tar.gz or linux-amd64.tar.gz
    url=$(echo "$raw" | grep '"browser_download_url":' | \
          grep -E "linux-${arch}${libc_suffix}\.tar\.gz\"" | head -1 | cut -d'"' -f4)

    # Fallback to non-suffixed if musl variant not found
    if [[ -z "$url" && -n "$libc_suffix" ]]; then
        warn "musl-specific binary not found, trying generic Linux binary"
        url=$(echo "$raw" | grep '"browser_download_url":' | \
              grep -E "linux-${arch}\.tar\.gz\"" | head -1 | cut -d'"' -f4)
    fi

    # ... rest of function ...
}
```

**Testing:**
```bash
# Test on Alpine Linux (musl)
docker run --rm -it alpine:latest sh -c "wget -O- https://... | sh"

# Test on Ubuntu (glibc)
docker run --rm -it ubuntu:latest bash -c "curl -fsSL https://... | bash"
```

**Impact:**
- ✅ Proper Alpine Linux support
- ✅ Works in musl-based containers
- ✅ Backward compatible (falls back to generic binary)
- ⚠️ Adds complexity to download logic

---

### 3. Download Abstraction

#### Claude's Approach
```bash
download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null; then
        if [ -n "$output" ]; then
            curl -fsSL "$url" -o "$output"
        else
            curl -fsSL "$url"
        fi
    elif command -v wget >/dev/null; then
        if [ -n "$output" ]; then
            wget -qO "$output" "$url"
        else
            wget -qO- "$url"
        fi
    else
        echo "Error: curl or wget required"
        exit 1
    fi
}

# Usage
download_file "$url"               # stdout
download_file "$url" "/tmp/file"   # to file
```

**Pros:**
- Single function handles both curl and wget
- Same interface for stdout and file output
- Clean and minimal

#### sbx Current Approach
```bash
# lib/download.sh:24-89
download_file() {
    local url="$1"
    local output_file="$2"
    local timeout="${3:-${HTTP_DOWNLOAD_TIMEOUT_SEC}}"

    # Validate parameters
    require "URL" "$url" "download URL" || return 1
    require "OUTPUT_FILE" "$output_file" "output file path" || return 1

    # ... extensive validation and error handling ...
}

# lib/common.sh also has safe_http_get()
safe_http_get() {
    local url="$1"
    local output="${2:-}"
    local timeout="${NETWORK_TIMEOUT_SEC:-5}"

    if have curl; then
        if [[ -n "$output" ]]; then
            curl -fsSL --max-time "$timeout" --connect-timeout "$timeout" "$url" -o "$output"
        else
            curl -fsSL --max-time "$timeout" --connect-timeout "$timeout" "$url"
        fi
    elif have wget; then
        # ... wget alternative ...
    fi
}
```

**Pros:**
- Comprehensive error handling
- Retry logic integration
- Validation and logging

**Cons:**
- Two different download functions (download_file, safe_http_get)
- More complex than necessary for simple cases
- Duplication between lib/download.sh and lib/common.sh

#### 🎯 Recommendation for sbx

**Consolidate Download Functions:**

1. **Keep lib/download.sh for complex downloads** (with retry, checksum, progress)
2. **Use lib/common.sh safe_http_get() for simple fetches** (JSON, small files)
3. **Remove duplication** - make download_file call safe_http_get internally

```bash
# lib/common.sh - Keep as is (simple, minimal)
safe_http_get() { ... }

# lib/download.sh - Use safe_http_get internally
download_file() {
    local url="$1"
    local output_file="$2"

    # Validation
    require "URL" "$url" "download URL" || return 1
    require "OUTPUT_FILE" "$output_file" "output file path" || return 1

    # Use safe_http_get from common.sh
    safe_http_get "$url" "$output_file" || return 1

    # Verify download
    verify_downloaded_file "$output_file" || return 1
}

# lib/download.sh - Add advanced version with retry
download_file_with_retry() {
    local url="$1"
    local output_file="$2"
    local max_retries="${3:-3}"

    retry_with_backoff "$max_retries" download_file "$url" "$output_file"
}
```

**Impact:**
- ✅ Less code duplication
- ✅ Clear separation: simple vs advanced downloads
- ✅ Easier to maintain

---

### 4. Error Handling Philosophy

#### Claude's Approach (Fail Fast)
```bash
set -e  # Exit on any error

# Minimal error messages
echo "Error: $reason"
exit 1
```

**Philosophy:**
- Fail immediately on any error
- Trust `set -e` to handle most cases
- Simple, clear error messages
- No recovery attempts

#### sbx Approach (Defensive Programming)
```bash
set -euo pipefail  # Stricter than Claude

# Extensive error handling
download_file() {
    # Validate inputs
    require "URL" "$url" || return 1

    # Try operation
    safe_http_get "$url" "$file" || {
        err "Download failed: $url"
        err "  Target: $file"
        err "  Check network connectivity"
        return 1
    }

    # Verify result
    verify_downloaded_file "$file" || {
        err "Verification failed"
        cleanup_partial_download "$file"
        return 1
    }
}
```

**Philosophy:**
- Validate everything before attempting
- Provide detailed error context
- Clean up on failure
- Return error codes for caller to handle

#### 🎯 Recommendation for sbx

**Current approach is BETTER for user-facing installer:**
- ✅ Better error messages help users troubleshoot
- ✅ Cleanup prevents corrupted state
- ✅ Validation catches issues early

**Minor improvement:**
```bash
# Add DEBUG mode toggle for minimal output
if [[ "${MINIMAL_ERRORS:-0}" == "1" ]]; then
    # Claude-style simple errors
    die() { echo "Error: $1" >&2; exit 1; }
else
    # Current detailed errors
    die() { err "$@"; exit 1; }
fi
```

This allows power users to opt into minimal output for automated deployments.

---

### 5. Checksum Verification

#### Claude's Approach
```bash
# Inline checksum verification
expected="$checksum"
actual="$(sha256sum "$file" | cut -d' ' -f1)"

if [ "$actual" != "$expected" ]; then
    rm -f "$file"
    echo "Error: Checksum mismatch"
    echo "  Expected: $expected"
    echo "  Got: $actual"
    exit 1
fi
```

**Pros:**
- Simple and clear
- Immediate verification
- Automatic cleanup on failure

#### sbx Approach
```bash
# lib/checksum.sh - Modular verification
verify_singbox_binary() {
    local pkg="$1"
    local tag="$2"
    local platform="$3"

    # Fetch checksums from GitHub
    # Parse SHA256SUMS file
    # Compare checksums
    # Provide detailed error messages
}
```

**Pros:**
- More robust (handles SHA256SUMS file parsing)
- Better error messages
- Supports multiple platforms
- Centralized in module

**Cons:**
- More complex
- Requires separate checksums file download

#### 🎯 Recommendation for sbx

**Current approach is BETTER:**
- ✅ Official sing-box provides SHA256SUMS file
- ✅ Our implementation properly uses it
- ✅ More secure (verifies checksum source)

**No changes needed.**

---

## Priority Recommendations

### HIGH Priority (Implement Soon)

1. **Make jq Optional**
   - Estimated effort: 1 hour
   - Impact: HIGH (supports minimal systems)
   - Implementation: Update `ensure_tools()` to treat jq as optional
   - Testing: Verify lib/tools.sh fallbacks work

2. **Add musl Detection**
   - Estimated effort: 2 hours
   - Impact: HIGH (Alpine Linux support)
   - Implementation: Add `detect_libc()` function
   - Testing: Test on Alpine and Ubuntu containers

### MEDIUM Priority (Consider for Next Release)

3. **Consolidate Download Functions**
   - Estimated effort: 3 hours
   - Impact: MEDIUM (code quality)
   - Implementation: Refactor lib/download.sh and lib/common.sh
   - Testing: Full integration test suite

4. **Add Minimal Error Mode**
   - Estimated effort: 1 hour
   - Impact: LOW (nice to have)
   - Implementation: `MINIMAL_ERRORS=1` environment variable
   - Testing: Verify both modes work

### LOW Priority (Future Consideration)

5. **Pure Bash JSON Parser**
   - Estimated effort: 8+ hours
   - Impact: LOW (lib/tools.sh fallback already works)
   - Implementation: Replace python fallback with bash regex
   - Testing: Extensive JSON parsing tests

---

## Implementation Plan

### Phase 1: Make jq Optional (Week 1)
```bash
# Task 1.1: Update ensure_tools()
# Task 1.2: Test lib/tools.sh fallbacks
# Task 1.3: Update documentation
# Task 1.4: Add integration tests
```

### Phase 2: Add musl Support (Week 2)
```bash
# Task 2.1: Implement detect_libc()
# Task 2.2: Update download_singbox()
# Task 2.3: Test on Alpine Linux
# Task 2.4: Update CLAUDE.md
```

### Phase 3: Code Consolidation (Week 3)
```bash
# Task 3.1: Audit download functions
# Task 3.2: Refactor lib/download.sh
# Task 3.3: Update all callers
# Task 3.4: Full regression testing
```

---

## Testing Checklist

After each improvement, verify:

- [ ] One-liner install works: `bash <(curl -fsSL ...)`
- [ ] Git clone install works: `git clone && bash install_multi.sh`
- [ ] Reality-only mode works (auto-detect IP)
- [ ] Full setup works (with domain)
- [ ] Alpine Linux support (musl)
- [ ] Ubuntu support (glibc)
- [ ] Without jq installed
- [ ] Without wget (curl only)
- [ ] Without curl (wget only)
- [ ] Checksum verification works
- [ ] Service starts successfully
- [ ] Client connection works

---

## Conclusion

**sbx's installation script is already more sophisticated than Claude's bootstrap.sh** in most areas. The main learnings are:

1. ✅ **Make jq optional** - Low-hanging fruit, high impact
2. ✅ **Add musl detection** - Important for Alpine/Docker users
3. ✅ **Keep our comprehensive error handling** - Better UX
4. ✅ **Keep our modular architecture** - Better maintainability

Claude's script teaches us that **minimal dependencies and graceful degradation** are valuable for bootstrap scripts, but our comprehensive approach is appropriate for a full-featured installer.

**Next Steps:**
1. Implement HIGH priority recommendations
2. Test on Alpine Linux
3. Update documentation
4. Create PR with improvements

---

**Document Version:** 1.0
**Author:** Analysis of Claude bootstrap.sh vs sbx install_multi.sh
**Date:** 2025-11-18
