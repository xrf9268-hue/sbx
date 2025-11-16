# Multi-Phase Improvement Plan: Reality Configuration Enhancements

**Created:** 2025-11-16
**Based on:** [REALITY_COMPLIANCE_REVIEW.md](./REALITY_COMPLIANCE_REVIEW.md)
**Target:** Address identified gaps and align with latest sing-box official documentation

---

## Executive Summary

This document outlines a comprehensive, multi-phase plan to enhance the sbx project's VLESS + REALITY + Vision implementation by addressing identified gaps and ensuring alignment with sing-box 1.12.0+ best practices.

**Current Status:** ✅ Implementation is fully compliant
**Goal:** Add robustness through testing, documentation, and future-proofing

---

## Phase 0: Foundation (COMPLETED ✅)

**Timeline:** Immediate
**Priority:** CRITICAL
**Status:** ✅ COMPLETED

### Objectives
- Initialize official sing-box documentation submodule
- Establish baseline for comparison with official standards

### Tasks

#### Task 0.1: Initialize Submodule ✅
**Status:** COMPLETED (2025-11-16)

```bash
git submodule update --init --recursive
```

**Verification:**
```bash
# Verify submodule is properly initialized
ls -la docs/sing-box-official/docs/configuration/inbound/vless.md
ls -la docs/sing-box-official/docs/configuration/shared/tls.md
```

**Result:** Submodule initialized successfully with commit `43fef1da`

#### Task 0.2: Document Submodule Management ✅
**File:** `README.md` (to be updated)

**Required Changes:**
1. Add "Official Documentation" section to README
2. Include initialization instructions
3. Document update procedures
4. Reference official docs in development workflow

**Template:**
```markdown
## Official Documentation Access

This project includes the official sing-box repository as a git submodule for easy access to the latest documentation.

### First-Time Setup
bash
git submodule update --init --recursive


### Update to Latest Official Docs
bash
git submodule update --remote docs/sing-box-official


### Key Documentation Paths
- **VLESS Configuration:** `docs/sing-box-official/docs/configuration/inbound/vless.md`
- **Reality/TLS Configuration:** `docs/sing-box-official/docs/configuration/shared/tls.md`
- **Migration Guide:** `docs/sing-box-official/docs/migration.md`
```

**Acceptance Criteria:**
- [x] Submodule initialized
- [ ] README updated with submodule instructions
- [ ] Developers can access official docs locally

---

## Phase 1: Documentation & Knowledge Base

**Timeline:** Week 1
**Priority:** HIGH
**Estimated Effort:** 8-12 hours

### Objectives
- Document sing-box vs Xray differences
- Create comprehensive troubleshooting guide
- Establish best practices documentation

### Tasks

#### Task 1.1: Document sing-box vs Xray Differences
**File:** `docs/SING_BOX_VS_XRAY.md` (new)

**Content Requirements:**

1. **Configuration Format Differences**
   - sing-box native format vs V2Ray format
   - Field name mapping
   - Structure differences

2. **Reality Implementation Differences**
   ```markdown
   | Feature | sing-box | Xray | Impact |
   |---------|----------|------|---------|
   | Short ID Length | 0-8 hex chars | 0-16 hex chars | Client must match server |
   | Generation Command | `sing-box generate reality-keypair` | `xray x25519` | Different binaries |
   | Config Structure | `tls.reality` | `streamSettings.realitySettings` | JSON path differs |
   | Flow Field Location | `users[].flow` | `clients[].flow` | Structure difference |
   ```

3. **Client Compatibility Matrix**
   ```markdown
   | Client | sing-box Core | Xray Core | Notes |
   |--------|---------------|-----------|-------|
   | v2rayN | ✅ | ❌ | Must switch to sing-box core |
   | Clash Meta | ✅ | ✅ | Auto-detects based on config |
   | NekoRay | ✅ | ✅ | Manual core selection |
   | Shadowrocket | ✅ | ❌ | iOS, sing-box only |
   ```

4. **Migration Guide from Xray**
   - Converting Xray Reality configs to sing-box
   - Short ID truncation (16 chars → 8 chars)
   - Client reconfiguration steps

**Acceptance Criteria:**
- [ ] Document created with all sections
- [ ] Code examples for both formats
- [ ] Migration scripts/tools documented
- [ ] Linked from main README

#### Task 1.2: Enhance CLAUDE.md with Reality Best Practices
**File:** `CLAUDE.md` (update)

**Additions:**

1. **Reality Configuration Section**
   ```markdown
   ### Reality Protocol Best Practices (sing-box 1.12.0+)

   #### Short ID Generation
   - **ALWAYS** use `openssl rand -hex 4` for 8-character short IDs
   - **NEVER** use `openssl rand -hex 8` (produces 16 chars, invalid for sing-box)
   - **ALWAYS** validate immediately: `validate_short_id "$SID"`

   #### Configuration Structure Rules
   - Reality **MUST** be nested under `tls.reality` (not top-level)
   - Flow field **MUST** be `"xtls-rprx-vision"` for Vision protocol
   - Short ID **MUST** be array format: `["a1b2c3d4"]` not string `"a1b2c3d4"`
   - Transport **MUST** be TCP (implicit or explicit) for Vision flow

   #### Official Reference Locations
   - VLESS inbound: `docs/sing-box-official/docs/configuration/inbound/vless.md`
   - Reality fields: `docs/sing-box-official/docs/configuration/shared/tls.md#reality-fields`
   - Migration guide: `docs/sing-box-official/docs/migration.md`
   ```

2. **Configuration Validation Workflow**
   ```markdown
   #### Reality Configuration Validation Checklist
   1. ✅ Generate keypair: `sing-box generate reality-keypair`
   2. ✅ Generate short_id: `openssl rand -hex 4` (exactly 4, not 8!)
   3. ✅ Validate short_id: `validate_short_id "$SID"`
   4. ✅ Structure check: Reality nested under `tls.reality`
   5. ✅ Flow check: `"flow": "xtls-rprx-vision"` in users array
   6. ✅ Short ID format: Array `["$SID"]` not string `"$SID"`
   7. ✅ Config validation: `sing-box check -c /etc/sing-box/config.json`
   8. ✅ Service test: `systemctl restart sing-box && systemctl status sing-box`
   ```

**Acceptance Criteria:**
- [ ] CLAUDE.md updated with Reality section
- [ ] Validation checklist added
- [ ] Official docs referenced
- [ ] Examples added for common scenarios

#### Task 1.3: Create Troubleshooting Guide
**File:** `docs/REALITY_TROUBLESHOOTING.md` (new)

**Content Structure:**

1. **Configuration Issues**
   - Short ID validation errors
   - Keypair generation failures
   - TLS nesting errors
   - Flow field mismatches

2. **Client Connection Issues**
   - "network unreachable" with Reality
   - Handshake failures
   - SNI mismatch errors
   - Public/private key mismatches

3. **Service Startup Issues**
   - Port conflicts
   - Configuration syntax errors
   - Permission issues
   - Certificate problems

4. **Diagnostic Commands**
   ```bash
   # Reality-specific diagnostics
   sing-box check -c /etc/sing-box/config.json
   jq '.inbounds[0].tls.reality' /etc/sing-box/config.json
   jq '.inbounds[0].users[0].flow' /etc/sing-box/config.json

   # Service diagnostics
   systemctl status sing-box
   journalctl -u sing-box -n 50 --no-pager
   ss -lntp | grep -E ':(443|8443|8444)'
   ```

**Acceptance Criteria:**
- [ ] Common issues documented with solutions
- [ ] Diagnostic commands provided
- [ ] Root cause analysis for each issue
- [ ] Links to official documentation

---

## Phase 2: Testing Infrastructure

**Timeline:** Week 2-3
**Priority:** HIGH
**Estimated Effort:** 16-24 hours

### Objectives
- Establish comprehensive test suite for Reality configuration
- Achieve >80% test coverage for Reality-related functions
- Integrate tests into CI/CD pipeline

### Tasks

#### Task 2.1: Create Reality Unit Test Suite
**File:** `tests/test_reality.sh` (new)

**Test Categories:**

1. **Configuration Generation Tests**
   ```bash
   test_reality_config_structure() {
     # Generate Reality config
     local config
     config=$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")

     # Verify JSON structure
     echo "$config" | jq -e '.type == "vless"' || fail "Wrong protocol type"
     echo "$config" | jq -e '.users[0].flow == "xtls-rprx-vision"' || fail "Wrong flow"
     echo "$config" | jq -e '.tls.reality.enabled == true' || fail "Reality not enabled"
     echo "$config" | jq -e '.tls.reality.short_id | type == "array"' || fail "Short ID not array"

     pass
   }

   test_short_id_array_format() {
     local config
     config=$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")

     # Verify short_id is array, not string
     local sid_type
     sid_type=$(echo "$config" | jq -r '.tls.reality.short_id | type')
     [[ "$sid_type" == "array" ]] || fail "Short ID must be array, got: $sid_type"

     # Verify array has one element
     local sid_count
     sid_count=$(echo "$config" | jq -r '.tls.reality.short_id | length')
     [[ "$sid_count" -eq 1 ]] || fail "Short ID array must have 1 element, got: $sid_count"

     pass
   }

   test_tls_reality_nesting() {
     local config
     config=$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")

     # Verify Reality is under tls, not top-level
     echo "$config" | jq -e '.tls.reality' || fail "Reality not nested under tls"
     echo "$config" | jq -e '.reality' && fail "Reality should not be top-level"

     pass
   }

   test_required_fields_present() {
     local config
     config=$(create_reality_inbound "$UUID" 443 "::" "www.microsoft.com" "$PRIV" "$SID")

     # Server-side required fields
     echo "$config" | jq -e '.tls.reality.private_key' || fail "Missing private_key"
     echo "$config" | jq -e '.tls.reality.short_id' || fail "Missing short_id"
     echo "$config" | jq -e '.tls.reality.handshake.server' || fail "Missing handshake.server"
     echo "$config" | jq -e '.tls.reality.handshake.server_port' || fail "Missing handshake.server_port"

     pass
   }
   ```

2. **Validation Tests**
   ```bash
   test_short_id_length_limits() {
     # Valid: 1-8 hex characters
     validate_short_id "a" || fail "Single char should be valid"
     validate_short_id "ab" || fail "2 chars should be valid"
     validate_short_id "abcd1234" || fail "8 chars should be valid"

     # Invalid: 0 or >8 characters
     validate_short_id "" && fail "Empty should be invalid"
     validate_short_id "abcd12345" && fail "9 chars should be invalid"

     pass
   }

   test_invalid_short_id_rejected() {
     # Invalid characters
     validate_short_id "gggg" && fail "Non-hex chars should be invalid"
     validate_short_id "12-34" && fail "Special chars should be invalid"
     validate_short_id "ab cd" && fail "Spaces should be invalid"

     # Invalid format
     validate_short_id "0x1234" && fail "0x prefix should be invalid"

     pass
   }

   test_keypair_format_validation() {
     # Valid base64-like keypairs
     local valid_priv="UuMBgl7MXTPx9inmQp2UC7Jcnwc6XYbwDNebonM-FCc"
     local valid_pub="jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
     validate_reality_keypair "$valid_priv" "$valid_pub" || fail "Valid keypair rejected"

     # Invalid: empty keys
     validate_reality_keypair "" "$valid_pub" && fail "Empty private key should be invalid"
     validate_reality_keypair "$valid_priv" "" && fail "Empty public key should be invalid"

     # Invalid: non-base64 characters
     validate_reality_keypair "invalid@key" "$valid_pub" && fail "Invalid private key accepted"

     pass
   }
   ```

3. **Export Format Tests**
   ```bash
   test_uri_format_compliance() {
     local uri
     uri=$(export_uri reality)

     # Verify URI components
     [[ "$uri" =~ ^vless:// ]] || fail "URI must start with vless://"
     [[ "$uri" =~ security=reality ]] || fail "Missing security=reality"
     [[ "$uri" =~ flow=xtls-rprx-vision ]] || fail "Missing flow=xtls-rprx-vision"
     [[ "$uri" =~ type=tcp ]] || fail "Missing type=tcp"
     [[ "$uri" =~ pbk= ]] || fail "Missing public key (pbk)"
     [[ "$uri" =~ sid= ]] || fail "Missing short ID (sid)"

     pass
   }

   test_flow_field_in_all_exports() {
     # v2rayN JSON export
     local v2rayn_json
     v2rayn_json=$(export_v2rayn_json reality)
     echo "$v2rayn_json" | jq -e '.outbounds[0].settings.vnext[0].users[0].flow == "xtls-rprx-vision"' || \
       fail "v2rayN: Missing flow field"

     # Clash YAML export
     local clash_yaml
     clash_yaml=$(export_clash_yaml reality)
     echo "$clash_yaml" | grep -q "flow: xtls-rprx-vision" || fail "Clash: Missing flow field"

     # URI export
     local uri
     uri=$(export_uri reality)
     [[ "$uri" =~ flow=xtls-rprx-vision ]] || fail "URI: Missing flow field"

     pass
   }

   test_public_key_not_private_key() {
     # Ensure exports use public key, not private key
     local v2rayn_json
     v2rayn_json=$(export_v2rayn_json reality)

     # Should contain public key
     echo "$v2rayn_json" | jq -e ".outbounds[0].streamSettings.realitySettings.publicKey == \"$PUBLIC_KEY\"" || \
       fail "Public key not found in export"

     # Should NOT contain private key
     echo "$v2rayn_json" | grep -q "$PRIV" && fail "Private key leaked in client export!"

     pass
   }
   ```

4. **Integration Tests**
   ```bash
   test_end_to_end_reality_setup() {
     # Full setup simulation
     export UUID=$(generate_uuid)
     export DOMAIN="test.example.com"
     export REALITY_PORT_CHOSEN=443

     # Generate materials
     local keypair
     keypair=$(generate_reality_keypair)
     read -r PRIV PUB <<< "$keypair"
     export PRIV PUB

     export SID=$(openssl rand -hex 4)
     validate_short_id "$SID" || fail "Generated invalid short ID"

     # Generate configuration
     local config
     config=$(create_reality_inbound "$UUID" "$REALITY_PORT_CHOSEN" "::" "www.microsoft.com" "$PRIV" "$SID")

     # Validate with sing-box (requires binary)
     if have sing-box; then
       echo "$config" > /tmp/test-reality-config.json
       sing-box check -c /tmp/test-reality-config.json || fail "Config validation failed"
       rm -f /tmp/test-reality-config.json
     fi

     pass
   }
   ```

**Test Framework Structure:**
```bash
#!/usr/bin/env bash
# tests/test_reality.sh - Reality configuration test suite

set -euo pipefail

# Source modules
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/export.sh"
source "${LIB_DIR}/generators.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
  ((TESTS_PASSED++))
  echo "✓ ${FUNCNAME[1]}"
}

fail() {
  ((TESTS_FAILED++))
  echo "✗ ${FUNCNAME[1]}: $1"
  return 1
}

# Run all tests
run_tests() {
  echo "Reality Configuration Test Suite"
  echo "================================"

  # Configuration generation tests
  test_reality_config_structure
  test_short_id_array_format
  test_tls_reality_nesting
  test_required_fields_present

  # Validation tests
  test_short_id_length_limits
  test_invalid_short_id_rejected
  test_keypair_format_validation
  test_sni_domain_validation

  # Export format tests
  test_uri_format_compliance
  test_flow_field_in_all_exports
  test_public_key_not_private_key
  test_v2rayn_json_structure
  test_clash_yaml_structure

  # Integration tests
  test_end_to_end_reality_setup

  # Report
  echo ""
  echo "================================"
  echo "Tests run: $TESTS_RUN"
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"

  [[ $TESTS_FAILED -eq 0 ]] && echo "✓ All tests passed!" || echo "✗ Some tests failed"
  return $TESTS_FAILED
}

# Execute tests
run_tests
```

**Acceptance Criteria:**
- [ ] Test suite created with >15 test cases
- [ ] All test categories covered
- [ ] Tests pass on clean installation
- [ ] Tests integrated into Makefile

#### Task 2.2: Add Validation Tests to CI
**File:** `.github/workflows/test.yml` (new)

**Workflow Definition:**
```yaml
name: Test Suite

on:
  push:
    branches: [ main, dev, 'claude/**' ]
  pull_request:
    branches: [ main ]

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq openssl

      - name: Download sing-box binary
        run: |
          wget -q https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz
          tar -xzf sing-box-linux-amd64.tar.gz
          sudo mv sing-box-*/sing-box /usr/local/bin/
          sudo chmod +x /usr/local/bin/sing-box

      - name: Run Reality tests
        run: |
          bash tests/test_reality.sh

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/

  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: unit-tests

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Run full installation (Reality-only)
        run: |
          sudo bash install_multi.sh <<EOF
          1
          EOF

      - name: Verify service status
        run: |
          systemctl is-active sing-box || exit 1
          /usr/local/bin/sing-box check -c /etc/sing-box/config.json || exit 1

      - name: Test configuration exports
        run: |
          sbx export uri reality
          sbx export v2rayn reality
          sbx export clash reality

      - name: Verify configuration structure
        run: |
          # Verify Reality is properly nested
          jq -e '.inbounds[0].tls.reality' /etc/sing-box/config.json || exit 1
          jq -e '.inbounds[0].users[0].flow == "xtls-rprx-vision"' /etc/sing-box/config.json || exit 1
          jq -e '.inbounds[0].tls.reality.short_id | type == "array"' /etc/sing-box/config.json || exit 1
```

**Acceptance Criteria:**
- [ ] CI workflow created
- [ ] Unit tests run on every push
- [ ] Integration tests verify full installation
- [ ] Test failures block merges

#### Task 2.3: Create Test Coverage Report
**File:** `tests/coverage.sh` (new)

**Coverage Metrics:**
```bash
#!/usr/bin/env bash
# Generate test coverage report for Reality functions

COVERAGE_DIR="test-results/coverage"
mkdir -p "$COVERAGE_DIR"

# Functions to test
FUNCTIONS=(
  "generate_reality_keypair"
  "validate_short_id"
  "validate_reality_sni"
  "validate_reality_keypair"
  "create_reality_inbound"
  "export_uri:reality"
  "export_v2rayn_json:reality"
  "export_clash_yaml:reality"
)

# Generate coverage report
echo "Function Coverage Report" > "$COVERAGE_DIR/coverage.txt"
echo "========================" >> "$COVERAGE_DIR/coverage.txt"

for func in "${FUNCTIONS[@]}"; do
  if grep -q "test.*${func%%:*}" tests/test_reality.sh; then
    echo "✓ $func" >> "$COVERAGE_DIR/coverage.txt"
  else
    echo "✗ $func (NOT TESTED)" >> "$COVERAGE_DIR/coverage.txt"
  fi
done

cat "$COVERAGE_DIR/coverage.txt"
```

**Acceptance Criteria:**
- [ ] Coverage script created
- [ ] >80% function coverage achieved
- [ ] Coverage report generated in CI
- [ ] Coverage badge added to README

---

## Phase 3: Code Enhancements

**Timeline:** Week 4
**Priority:** MEDIUM
**Estimated Effort:** 12-16 hours

### Objectives
- Add transport+security pairing validation
- Extract magic constants
- Improve error messages with actionable guidance

### Tasks

#### Task 3.1: Transport+Security Pairing Validation
**File:** `lib/validation.sh` (update)

**New Function:**
```bash
#==============================================================================
# Transport and Security Pairing Validation
#==============================================================================

# Validate transport+security+flow pairing for VLESS
# Vision flow requires TCP transport with Reality security
validate_transport_security_pairing() {
  local transport="${1:-tcp}"  # Default to TCP
  local security="${2:-}"      # TLS, Reality, or none
  local flow="${3:-}"          # xtls-rprx-vision or empty

  # Validate Vision flow requirements
  if [[ "$flow" == "xtls-rprx-vision" ]]; then
    # Vision REQUIRES TCP transport
    if [[ "$transport" != "tcp" ]]; then
      err "Vision flow (xtls-rprx-vision) requires TCP transport, got: $transport"
      err "Valid combinations:"
      err "  - Transport: tcp, Security: reality, Flow: xtls-rprx-vision"
      return 1
    fi

    # Vision REQUIRES Reality security
    if [[ "$security" != "reality" ]]; then
      err "Vision flow (xtls-rprx-vision) requires Reality security, got: $security"
      err "For TLS security, use flow=\"\" (empty flow field)"
      return 1
    fi
  fi

  # Validate Reality security requirements
  if [[ "$security" == "reality" ]]; then
    # Reality works with TCP (and theoretically others, but Vision requires TCP)
    if [[ -n "$flow" && "$flow" != "xtls-rprx-vision" ]]; then
      warn "Reality security with non-Vision flow: $flow"
      warn "Common configuration uses flow=\"xtls-rprx-vision\" with Reality"
    fi
  fi

  # Validate incompatible combinations
  case "$transport:$security" in
    "ws:reality")
      err "WebSocket transport is incompatible with Reality security"
      err "Use: ws+tls or tcp+reality"
      return 1
      ;;
    "grpc:reality")
      err "gRPC transport is incompatible with Reality security"
      err "Use: grpc+tls or tcp+reality"
      return 1
      ;;
    "http:reality")
      err "HTTP transport is incompatible with Reality security"
      err "Use: tcp+reality for Vision protocol"
      return 1
      ;;
  esac

  success "Transport+security+flow pairing validated: $transport+$security${flow:++$flow}"
  return 0
}

# Export function
export -f validate_transport_security_pairing
```

**Integration Points:**
1. Call in `create_reality_inbound()` before config generation
2. Add to `validate_config_vars()` pre-flight checks
3. Include in unit tests

**Acceptance Criteria:**
- [ ] Function created with comprehensive validation
- [ ] All invalid pairings rejected with helpful errors
- [ ] Valid pairings pass without warnings
- [ ] Integrated into config generation flow
- [ ] Unit tests cover all combinations

#### Task 3.2: Extract Magic Constants
**File:** `lib/common.sh` (update)

**New Constants:**
```bash
#==============================================================================
# Reality Protocol Constants
#==============================================================================

# Reality configuration defaults
readonly REALITY_DEFAULT_SNI="www.microsoft.com"
readonly REALITY_DEFAULT_HANDSHAKE_PORT=443
readonly REALITY_MAX_TIME_DIFF="1m"
readonly REALITY_FLOW_VISION="xtls-rprx-vision"

# Reality validation constraints
readonly REALITY_SHORT_ID_MIN_LENGTH=1
readonly REALITY_SHORT_ID_MAX_LENGTH=8
readonly REALITY_SHORT_ID_PATTERN="^[0-9a-fA-F]{${REALITY_SHORT_ID_MIN_LENGTH},${REALITY_SHORT_ID_MAX_LENGTH}}$"

# ALPN protocols for Reality
readonly REALITY_ALPN_H2="h2"
readonly REALITY_ALPN_HTTP11="http/1.1"
readonly REALITY_ALPN_PROTOCOLS="[\"${REALITY_ALPN_H2}\", \"${REALITY_ALPN_HTTP11}\"]"

# Reality fingerprint options
readonly REALITY_FINGERPRINT_CHROME="chrome"
readonly REALITY_FINGERPRINT_FIREFOX="firefox"
readonly REALITY_FINGERPRINT_SAFARI="safari"
readonly REALITY_FINGERPRINT_DEFAULT="$REALITY_FINGERPRINT_CHROME"

# Export constants
export REALITY_DEFAULT_SNI REALITY_DEFAULT_HANDSHAKE_PORT REALITY_MAX_TIME_DIFF
export REALITY_FLOW_VISION REALITY_SHORT_ID_PATTERN REALITY_ALPN_PROTOCOLS
export REALITY_FINGERPRINT_DEFAULT
```

**Refactoring Required:**

1. **config.sh:154** - Replace hardcoded flow
   ```bash
   # Before
   users: [{ uuid: $uuid, flow: "xtls-rprx-vision" }],

   # After
   users: [{ uuid: $uuid, flow: $flow }],

   # Pass constant as parameter
   --arg flow "$REALITY_FLOW_VISION"
   ```

2. **config.sh:172** - Replace hardcoded max_time_difference
   ```bash
   # Before
   max_time_difference: "1m"

   # After
   max_time_difference: $max_time_diff

   # Pass constant as parameter
   --arg max_time_diff "$REALITY_MAX_TIME_DIFF"
   ```

3. **config.sh:174** - Replace hardcoded ALPN
   ```bash
   # Before
   alpn: ["h2", "http/1.1"]

   # After
   alpn: $alpn

   # Pass constant as parameter (already JSON array string)
   --argjson alpn "$REALITY_ALPN_PROTOCOLS"
   ```

4. **validation.sh:296** - Use pattern constant
   ```bash
   # Before
   [[ "$sid" =~ ^[0-9a-fA-F]{1,8}$ ]]

   # After
   [[ "$sid" =~ $REALITY_SHORT_ID_PATTERN ]]
   ```

5. **export.sh:74,209** - Use fingerprint constant
   ```bash
   # Before
   fingerprint: "chrome"
   fp=chrome

   # After
   fingerprint: $fp
   fp=$fp

   # Use constant
   --arg fp "$REALITY_FINGERPRINT_DEFAULT"
   fp=${REALITY_FINGERPRINT_DEFAULT}
   ```

**Acceptance Criteria:**
- [ ] All magic numbers/strings extracted to constants
- [ ] Constants documented with comments
- [ ] All usages refactored to use constants
- [ ] No hardcoded values remain
- [ ] Tests verify constants are used correctly

#### Task 3.3: Enhance Error Messages
**File:** Multiple files in `lib/` (update)

**Improvement Pattern:**

**Before:**
```bash
[[ "$sid" =~ ^[0-9a-fA-F]{1,8}$ ]] || {
  err "Short ID must be 1-8 hexadecimal characters, got: $sid"
  return 1
}
```

**After:**
```bash
[[ "$sid" =~ ^[0-9a-fA-F]{1,8}$ ]] || {
  err "Invalid Reality short ID: $sid"
  err ""
  err "Requirements:"
  err "  - Length: 1-8 hexadecimal characters"
  err "  - Format: Only 0-9, a-f, A-F allowed"
  err "  - Example: a1b2c3d4"
  err ""
  err "Generate valid short ID:"
  err "  openssl rand -hex 4"
  err ""
  err "Note: sing-box uses 8-char short IDs (different from Xray's 16-char limit)"
  return 1
}
```

**Areas to Enhance:**
1. `validate_short_id()` - Add generation instructions
2. `validate_reality_keypair()` - Add generation command
3. `create_reality_inbound()` - Add configuration examples
4. `export_uri()` - Add client compatibility notes

**Acceptance Criteria:**
- [ ] All Reality error messages enhanced
- [ ] Every error includes actionable guidance
- [ ] Examples provided for correct usage
- [ ] Differences from Xray noted where relevant

---

## Phase 4: Advanced Features

**Timeline:** Week 5-6
**Priority:** LOW
**Estimated Effort:** 16-20 hours

### Objectives
- Add JSON schema validation
- Implement version compatibility checks
- Create automated integration tests

### Tasks

#### Task 4.1: JSON Schema Validation
**File:** `lib/schema_validator.sh` (new)

**Schema Definition:**
Create JSON schema for Reality configuration based on official sing-box schema.

**Validation Function:**
```bash
validate_config_schema() {
  local config_file="$1"
  local schema_file="${SCRIPT_DIR}/../schema/reality-config.schema.json"

  if ! have jq; then
    warn "jq not available, skipping schema validation"
    return 0
  fi

  # Validate JSON syntax first
  jq empty "$config_file" 2>/dev/null || {
    err "Invalid JSON syntax in configuration file"
    return 1
  }

  # Schema validation (if ajv or similar tool available)
  if have ajv; then
    ajv validate -s "$schema_file" -d "$config_file" || {
      err "Configuration does not match Reality schema"
      return 1
    }
  fi

  # Manual validation for key Reality fields
  jq -e '.inbounds[].tls.reality' "$config_file" >/dev/null || {
    warn "No Reality configuration found in inbounds"
  }

  return 0
}
```

**Schema File:** `schema/reality-config.schema.json`
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "sing-box Reality Configuration Schema",
  "type": "object",
  "required": ["inbounds"],
  "properties": {
    "inbounds": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string",
            "enum": ["vless"]
          },
          "users": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["uuid"],
              "properties": {
                "uuid": {
                  "type": "string",
                  "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
                },
                "flow": {
                  "type": "string",
                  "enum": ["", "xtls-rprx-vision"]
                }
              }
            }
          },
          "tls": {
            "type": "object",
            "properties": {
              "reality": {
                "type": "object",
                "required": ["enabled", "private_key", "short_id", "handshake"],
                "properties": {
                  "enabled": {
                    "type": "boolean",
                    "const": true
                  },
                  "private_key": {
                    "type": "string",
                    "minLength": 32
                  },
                  "short_id": {
                    "type": "array",
                    "items": {
                      "type": "string",
                      "pattern": "^[0-9a-fA-F]{1,8}$"
                    },
                    "minItems": 1
                  },
                  "handshake": {
                    "type": "object",
                    "required": ["server", "server_port"],
                    "properties": {
                      "server": {
                        "type": "string",
                        "format": "hostname"
                      },
                      "server_port": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 65535
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Acceptance Criteria:**
- [ ] Schema file created based on official specs
- [ ] Validation function implemented
- [ ] Integrated into `sing-box check` workflow
- [ ] Schema versioned for compatibility tracking

#### Task 4.2: Version Compatibility Checks
**File:** `lib/version_check.sh` (new)

**Version Detection:**
```bash
get_singbox_version() {
  local version_output
  version_output=$("$SB_BIN" version 2>&1)

  # Extract version number (e.g., "1.12.0")
  local version
  version=$(echo "$version_output" | grep -oP 'sing-box version \K[0-9]+\.[0-9]+\.[0-9]+')

  echo "$version"
}

compare_versions() {
  local version1="$1"
  local version2="$2"

  # Simple version comparison (semantic versioning)
  printf '%s\n%s\n' "$version1" "$version2" | sort -V | head -n1
}

validate_singbox_version() {
  local min_version="1.8.0"  # Reality requires 1.8.0+
  local recommended_version="1.12.0"  # Modern config format

  local current_version
  current_version=$(get_singbox_version)

  if [[ -z "$current_version" ]]; then
    warn "Could not detect sing-box version"
    return 0
  fi

  # Check minimum version
  local oldest
  oldest=$(compare_versions "$current_version" "$min_version")
  if [[ "$oldest" != "$min_version" ]]; then
    err "sing-box version $current_version is too old for Reality protocol"
    err "Minimum required: $min_version"
    err "Current: $current_version"
    err "Please upgrade: https://github.com/SagerNet/sing-box/releases"
    return 1
  fi

  # Check recommended version
  oldest=$(compare_versions "$current_version" "$recommended_version")
  if [[ "$oldest" != "$recommended_version" ]]; then
    warn "sing-box version $current_version detected"
    warn "Recommended: $recommended_version or later for modern config format"
    warn "Current: $current_version"
  else
    success "sing-box version $current_version (meets all requirements)"
  fi

  return 0
}
```

**Integration:**
- Call during installation pre-flight checks
- Display version warnings before config generation
- Add to `sbx status` command output

**Acceptance Criteria:**
- [ ] Version detection implemented
- [ ] Minimum version enforcement (1.8.0+)
- [ ] Recommended version warnings (1.12.0+)
- [ ] Integrated into installation flow

#### Task 4.3: Automated Integration Tests
**File:** `tests/integration/test_reality_connection.sh` (new)

**Docker-Based Client Testing:**
```bash
#!/usr/bin/env bash
# Integration test: Verify Reality connection with real client

set -euo pipefail

# Setup test environment
setup_test_server() {
  # Install sing-box server
  sudo bash install_multi.sh <<EOF
1
EOF

  # Export configuration
  URI=$(sbx export uri reality)
  CONFIG=$(sbx export v2rayn reality)

  echo "$URI" > /tmp/reality-uri.txt
  echo "$CONFIG" > /tmp/reality-client.json
}

# Test client connection
test_client_connection() {
  local client_type="$1"  # sing-box, v2ray, clash

  case "$client_type" in
    sing-box)
      # Use sing-box as client
      sing-box run -c /tmp/reality-client.json &
      local client_pid=$!
      sleep 5

      # Test connection through proxy
      curl -x socks5://127.0.0.1:10808 https://www.google.com -I -s || {
        kill $client_pid
        fail "Connection failed"
      }

      kill $client_pid
      ;;

    v2ray)
      # Docker container with v2rayN equivalent
      docker run -d --name v2ray-test \
        -v /tmp/reality-client.json:/etc/v2ray/config.json \
        v2fly/v2fly-core:latest

      sleep 5

      # Test connection
      docker exec v2ray-test curl https://www.google.com -I -s || fail "Connection failed"

      docker stop v2ray-test
      docker rm v2ray-test
      ;;
  esac

  pass
}

# Handshake validation test
test_reality_handshake() {
  # Monitor server logs during client connection
  journalctl -u sing-box -f > /tmp/server-logs.txt &
  local log_pid=$!

  # Connect client
  sing-box run -c /tmp/reality-client.json &
  local client_pid=$!

  sleep 10

  # Check for successful handshake in logs
  kill $log_pid
  kill $client_pid

  grep -q "Reality handshake" /tmp/server-logs.txt || warn "Handshake not logged"
  grep -q "error\|failed" /tmp/server-logs.txt && fail "Errors in server logs"

  pass
}

# Run tests
setup_test_server
test_client_connection sing-box
test_reality_handshake

echo "✓ Integration tests passed"
```

**CI Integration:**
Add to `.github/workflows/test.yml`:
```yaml
  integration-reality:
    name: Reality Connection Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup test environment
        run: tests/integration/test_reality_connection.sh
```

**Acceptance Criteria:**
- [ ] Integration test script created
- [ ] Tests verify actual connections
- [ ] Handshake validation included
- [ ] Runs in CI environment

---

## Phase 5: Documentation Finalization

**Timeline:** Week 7
**Priority:** MEDIUM
**Estimated Effort:** 6-8 hours

### Objectives
- Update all documentation with new features
- Create comprehensive examples repository
- Publish best practices guide

### Tasks

#### Task 5.1: Update README with Complete Workflow
**File:** `README.md` (update)

**Additions:**
1. Reality protocol overview
2. Quick start guide
3. Configuration examples
4. Testing instructions
5. Troubleshooting links

**Template Section:**
```markdown
## Reality Protocol Support

sbx-lite provides full support for VLESS + REALITY + Vision protocol with sing-box 1.12.0+ compatibility.

### Quick Start

bash
# Auto-detect server IP, Reality-only mode
bash <(curl -fsSL https://raw.githubusercontent.com/xrf9268-hue/sbx/main/install_multi.sh)

# Specify domain for full mode (Reality + WS-TLS + Hysteria2)
DOMAIN=your.domain.com bash install_multi.sh


### Reality Features

- ✅ **Zero Configuration**: No domain/certificate required for Reality-only mode
- ✅ **Auto IP Detection**: Automatically detects server public IP
- ✅ **Modern Standards**: Full compliance with sing-box 1.12.0+ configuration format
- ✅ **Multi-Format Export**: v2rayN, Clash, QR codes, subscription links
- ✅ **Production Grade**: SHA256 verification, comprehensive validation, automated testing

### Configuration Validation

Every Reality configuration is validated through multiple layers:

1. **Pre-Generation Validation**: UUID, keypair, short_id format checks
2. **Structure Validation**: JSON schema compliance, proper nesting
3. **Runtime Validation**: `sing-box check -c /etc/sing-box/config.json`
4. **Service Validation**: Port listening, log monitoring

### Testing

bash
# Run Reality unit tests
make test

# Run full integration tests
make integration-test

# Check test coverage
make coverage


### Documentation

- **Reality Compliance**: [REALITY_COMPLIANCE_REVIEW.md](docs/REALITY_COMPLIANCE_REVIEW.md)
- **sing-box vs Xray**: [SING_BOX_VS_XRAY.md](docs/SING_BOX_VS_XRAY.md)
- **Troubleshooting**: [REALITY_TROUBLESHOOTING.md](docs/REALITY_TROUBLESHOOTING.md)
- **Official Docs**: [docs/sing-box-official/](docs/sing-box-official/)
```

**Acceptance Criteria:**
- [ ] README updated with Reality section
- [ ] Quick start examples added
- [ ] Links to all documentation
- [ ] Testing instructions included

#### Task 5.2: Create Examples Repository
**Directory:** `examples/` (new)

**Structure:**
```
examples/
├── README.md
├── reality-only/
│   ├── server-config.json
│   ├── client-v2rayn.json
│   ├── client-clash.yaml
│   └── share-uri.txt
├── reality-with-ws/
│   ├── server-config.json
│   ├── client-reality.json
│   ├── client-ws.json
│   └── README.md
├── advanced/
│   ├── multiple-users.json
│   ├── custom-sni.json
│   ├── fallback-config.json
│   └── README.md
└── troubleshooting/
    ├── common-errors.md
    ├── debug-configs/
    └── test-scripts/
```

**Example Files:**

**`examples/reality-only/server-config.json`:**
```json
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-local"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "REPLACE_WITH_YOUR_UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "private_key": "REPLACE_WITH_YOUR_PRIVATE_KEY",
          "short_id": ["REPLACE_WITH_YOUR_SHORT_ID"],
          "handshake": {
            "server": "www.microsoft.com",
            "server_port": 443
          },
          "max_time_difference": "1m"
        },
        "alpn": ["h2", "http/1.1"]
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true
    }
  ]
}
```

**`examples/reality-only/README.md`:**
```markdown
# Reality-Only Configuration Example

This example demonstrates a minimal Reality-only server configuration.

## Requirements

- sing-box 1.8.0+ (1.12.0+ recommended)
- No domain or certificate required
- Public IPv4 address

## Setup Steps

1. **Generate UUID**:
   bash
   sing-box generate uuid


2. **Generate Reality Keypair**:
   bash
   sing-box generate reality-keypair

   Output:

   PrivateKey: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   PublicKey: YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY


3. **Generate Short ID** (8 hex characters):
   bash
   openssl rand -hex 4

   Output: `a1b2c3d4`

4. **Replace Placeholders** in `server-config.json`:
   - `REPLACE_WITH_YOUR_UUID` → UUID from step 1
   - `REPLACE_WITH_YOUR_PRIVATE_KEY` → PrivateKey from step 2
   - `REPLACE_WITH_YOUR_SHORT_ID` → Short ID from step 3

5. **Validate Configuration**:
   bash
   sing-box check -c server-config.json


6. **Start Server**:
   bash
   sing-box run -c server-config.json


## Client Configuration

Use the PublicKey from step 2 to configure your client.

See `client-v2rayn.json` for v2rayN configuration example.

## Testing

bash
# On client machine, test connection
curl -x socks5://127.0.0.1:10808 https://www.google.com


## Troubleshooting

- **"network unreachable"**: Check `dns.strategy` is set to `"ipv4_only"` for IPv4-only servers
- **"handshake failed"**: Verify short_id matches between server and client
- **"invalid configuration"**: Ensure Reality is nested under `tls.reality`, not top-level
```

**Acceptance Criteria:**
- [ ] Examples directory created with structure
- [ ] Realistic configurations provided (with placeholders)
- [ ] READMEs with step-by-step instructions
- [ ] Troubleshooting notes for each example

#### Task 5.3: Publish Best Practices Guide
**File:** `docs/REALITY_BEST_PRACTICES.md` (new)

**Content Outline:**

1. **Security Best Practices**
   - Key generation and storage
   - Short ID randomness
   - SNI selection criteria
   - Certificate management

2. **Performance Optimization**
   - TCP Fast Open configuration
   - Multiplex settings
   - DNS caching
   - Connection pooling

3. **Deployment Patterns**
   - Single-protocol (Reality-only)
   - Multi-protocol (Reality + WS + Hysteria2)
   - High-availability setups
   - Load balancing

4. **Monitoring and Maintenance**
   - Log analysis
   - Performance metrics
   - Update procedures
   - Backup strategies

5. **Client Configuration**
   - Client selection guide
   - Configuration import methods
   - Troubleshooting client issues
   - Performance tuning

**Acceptance Criteria:**
- [ ] Best practices document created
- [ ] Each section has actionable guidance
- [ ] Examples and commands provided
- [ ] Linked from main README

---

## Implementation Timeline

### Week 1: Documentation & Knowledge Base (Phase 1)
- **Days 1-2**: Create SING_BOX_VS_XRAY.md
- **Days 3-4**: Update CLAUDE.md with Reality best practices
- **Days 5-7**: Create REALITY_TROUBLESHOOTING.md

### Week 2-3: Testing Infrastructure (Phase 2)
- **Days 1-5**: Create test_reality.sh with all test cases
- **Days 6-10**: Add CI workflows for automated testing
- **Days 11-14**: Achieve >80% coverage, generate reports

### Week 4: Code Enhancements (Phase 3)
- **Days 1-3**: Implement transport+security pairing validation
- **Days 4-5**: Extract magic constants to lib/common.sh
- **Days 6-7**: Enhance error messages with guidance

### Week 5-6: Advanced Features (Phase 4)
- **Days 1-4**: JSON schema validation implementation
- **Days 5-7**: Version compatibility checks
- **Days 8-14**: Automated integration tests with Docker

### Week 7: Documentation Finalization (Phase 5)
- **Days 1-2**: Update README with complete workflow
- **Days 3-5**: Create examples repository
- **Days 6-7**: Publish best practices guide

---

## Success Criteria

### Phase 1 Success Metrics
- [ ] Official submodule accessible locally
- [ ] Developers can reference official docs
- [ ] 3 comprehensive documentation files created
- [ ] All docs linked from README

### Phase 2 Success Metrics
- [ ] >15 unit tests passing
- [ ] >80% function coverage achieved
- [ ] CI runs tests on every commit
- [ ] Coverage report generated automatically

### Phase 3 Success Metrics
- [ ] Transport pairing validation prevents invalid configs
- [ ] No magic numbers/strings in code
- [ ] All error messages actionable
- [ ] Refactoring doesn't break existing functionality

### Phase 4 Success Metrics
- [ ] JSON schema validation available
- [ ] Version checks prevent incompatible setups
- [ ] Integration tests verify real connections
- [ ] All tests pass in CI environment

### Phase 5 Success Metrics
- [ ] README comprehensive and user-friendly
- [ ] >10 working configuration examples
- [ ] Best practices guide published
- [ ] Documentation receives positive feedback

---

## Risk Management

### Identified Risks

#### Risk 1: Test Coverage Gaps
**Impact:** Medium
**Probability:** Medium
**Mitigation:**
- Start with high-value test cases
- Prioritize Reality-specific functionality
- Incremental coverage improvements

#### Risk 2: CI/CD Performance
**Impact:** Low
**Probability:** Medium
**Mitigation:**
- Cache dependencies in workflows
- Parallel test execution
- Selective test runs (unit vs integration)

#### Risk 3: Documentation Maintenance
**Impact:** Medium
**Probability:** High
**Mitigation:**
- Version docs alongside code
- Automated doc generation where possible
- Regular review cycles

#### Risk 4: Breaking Changes in sing-box
**Impact:** High
**Probability:** Low
**Mitigation:**
- Version compatibility checks
- Official submodule tracking
- Migration guides for updates

---

## Maintenance Plan

### Continuous Improvement

#### Monthly Tasks
- Review official sing-box releases
- Update submodule to latest version
- Check for deprecated fields
- Update test suite

#### Quarterly Tasks
- Comprehensive documentation review
- Update examples with new features
- Performance benchmarking
- Security audit

#### Yearly Tasks
- Major version compatibility review
- Refactoring for code quality
- User feedback analysis
- Roadmap planning

### Version Tracking

| Component | Current | Target | Priority |
|-----------|---------|--------|----------|
| sing-box | 1.12.0+ | Latest stable | High |
| Tests | 0% | >80% coverage | Critical |
| Docs | Basic | Comprehensive | High |
| CI/CD | ShellCheck only | Full test suite | High |

---

## Conclusion

This multi-phase plan addresses all identified gaps from the compliance review while ensuring alignment with the latest sing-box official documentation. The phased approach allows for incremental improvements without disrupting existing functionality.

**Immediate Actions (Phase 0):**
- [x] Initialize submodule
- [ ] Update README with submodule instructions

**Priority Order:**
1. **Phase 2** (Testing) - Critical for preventing regressions
2. **Phase 1** (Documentation) - High value for users
3. **Phase 3** (Code Enhancement) - Improves robustness
4. **Phase 4** (Advanced Features) - Future-proofing
5. **Phase 5** (Documentation Finalization) - Polishing

**Timeline:** 7 weeks for complete implementation
**Estimated Total Effort:** 58-80 hours

**Next Steps:**
1. Review and approve this plan
2. Create GitHub issues for each phase
3. Assign tasks and set milestones
4. Begin Phase 1 documentation work

---

**Plan Version:** 1.0
**Last Updated:** 2025-11-16
**Status:** Ready for Review
