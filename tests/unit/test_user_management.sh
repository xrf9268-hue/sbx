#!/usr/bin/env bash
# tests/unit/test_user_management.sh - Unit tests for lib/users.sh
# Tests CRUD operations: user_add, user_list, user_remove, user_reset,
# legacy migration, and sync_users_to_config.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCK_TMP_DIR="$(mktemp -d /tmp/sbx-user-mgmt-locks.XXXXXX)"
export SBX_LOCK_FILE="${LOCK_TMP_DIR}/sbx.lock"
export SBX_STATE_LOCK_FILE="${LOCK_TMP_DIR}/sbx-state.lock"

# Disable strict mode so individual test failures don't abort the suite
set +e
set -o pipefail

# Source dependencies in order
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null || {
  echo "ERROR: Failed to load lib/common.sh"
  exit 1
}
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/users.sh" 2>/dev/null || {
  echo "ERROR: Failed to load lib/users.sh"
  exit 1
}

# Disable traps after loading modules
trap - EXIT INT TERM
trap 'rm -rf "${LOCK_TMP_DIR}"' EXIT
set +e

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

test_result() {
  local test_name="$1"
  local result="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "${result}" == "pass" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} ${test_name}"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗${NC} ${test_name}"
  fi
}

# Create a temporary state file pre-populated with a single legacy UUID
_make_legacy_state() {
  local f="$1"
  local uuid="${2:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
  cat >"${f}" <<JSON
{
  "version": "1.0",
  "installed_at": "2026-01-01T00:00:00Z",
  "mode": "reality_only",
  "server": {"domain": "test.example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "${uuid}",
      "public_key": "testpubkey",
      "short_id": "abcd1234",
      "sni": "www.microsoft.com"
    }
  }
}
JSON
  chmod 600 "${f}"
}

# Create a temporary state file pre-populated with a users array
_make_state_with_users() {
  local f="$1"
  cat >"${f}" <<'JSON'
{
  "version": "1.0",
  "installed_at": "2026-01-01T00:00:00Z",
  "mode": "reality_only",
  "server": {"domain": "test.example.com", "ip": null},
  "protocols": {
    "reality": {
      "enabled": true,
      "port": 443,
      "uuid": "11111111-1111-1111-1111-111111111111",
      "users": [
        {"name": "alice", "uuid": "11111111-1111-1111-1111-111111111111", "created_at": "2026-01-01T00:00:00Z"}
      ],
      "public_key": "testpubkey",
      "short_id": "abcd1234",
      "sni": "www.microsoft.com"
    }
  }
}
JSON
  chmod 600 "${f}"
}

#==============================================================================
# Test: _load_users — legacy migration
#==============================================================================

test_legacy_migration() {
  echo ""
  echo "Testing legacy UUID migration..."

  local tmp
  tmp=$(mktemp)
  _make_legacy_state "${tmp}" "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  export TEST_STATE_FILE="${tmp}"

  local users
  users=$(_load_users 2>/dev/null) || true

  # Should produce a one-element array with name "default"
  local count name uuid
  count=$(echo "${users}" | jq 'length' 2>/dev/null || echo 0)
  name=$(echo "${users}" | jq -r '.[0].name // empty' 2>/dev/null || true)
  uuid=$(echo "${users}" | jq -r '.[0].uuid // empty' 2>/dev/null || true)

  [[ "${count}" -eq 1 ]] &&
    test_result "migrates single legacy UUID to array" "pass" ||
    test_result "migrates single legacy UUID to array (count=${count})" "fail"

  [[ "${name}" == "default" ]] &&
    test_result "auto-names migrated user 'default'" "pass" ||
    test_result "auto-names migrated user 'default' (got '${name}')" "fail"

  [[ "${uuid}" == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]] &&
    test_result "preserves legacy UUID value" "pass" ||
    test_result "preserves legacy UUID value (got '${uuid}')" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Test: user_add
#==============================================================================

test_user_add_generates_uuid() {
  echo ""
  echo "Testing user_add UUID generation..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  user_add --name "bob" >/dev/null 2>&1

  local users
  users=$(_load_users 2>/dev/null) || true
  local bob_uuid
  bob_uuid=$(echo "${users}" | jq -r '.[] | select(.name == "bob") | .uuid' 2>/dev/null || true)

  if [[ "${bob_uuid}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    test_result "generates valid UUID for new user" "pass"
  else
    test_result "generates valid UUID for new user (got '${bob_uuid}')" "fail"
  fi

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

test_user_add_custom_name() {
  echo ""
  echo "Testing user_add --name..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  user_add --name "carol" >/dev/null 2>&1

  local users
  users=$(_load_users 2>/dev/null) || true
  local found
  found=$(echo "${users}" | jq -r '.[] | select(.name == "carol") | .name' 2>/dev/null || true)

  [[ "${found}" == "carol" ]] &&
    test_result "stores user with given name" "pass" ||
    test_result "stores user with given name (found='${found}')" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

test_user_add_auto_name() {
  echo ""
  echo "Testing user_add auto-naming..."

  local tmp
  tmp=$(mktemp)
  _make_legacy_state "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # First add should become user2 (default is user1 from migration)
  user_add >/dev/null 2>&1

  local users
  users=$(_load_users 2>/dev/null) || true
  local found
  found=$(echo "${users}" | jq -r '.[] | select(.name == "user2") | .name' 2>/dev/null || true)

  [[ "${found}" == "user2" ]] &&
    test_result "auto-names second user 'user2'" "pass" ||
    test_result "auto-names second user 'user2' (found='${found}')" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

test_user_add_duplicate_name_fails() {
  echo ""
  echo "Testing user_add duplicate name rejection..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # "alice" already exists in the state file
  local output
  output=$(user_add --name "alice" 2>&1) || true

  # Count should still be 1
  local users count
  users=$(_load_users 2>/dev/null) || true
  count=$(echo "${users}" | jq 'length' 2>/dev/null || echo 0)

  [[ "${count}" -eq 1 ]] &&
    test_result "rejects duplicate name and leaves count unchanged" "pass" ||
    test_result "rejects duplicate name (count=${count}, expected 1)" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Test: user_list
#==============================================================================

test_user_list_shows_table() {
  echo ""
  echo "Testing user_list output..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  local output
  output=$(user_list 2>/dev/null) || true

  echo "${output}" | grep -q "NAME" &&
    test_result "output contains NAME header" "pass" ||
    test_result "output contains NAME header" "fail"

  echo "${output}" | grep -q "UUID" &&
    test_result "output contains UUID header" "pass" ||
    test_result "output contains UUID header" "fail"

  echo "${output}" | grep -q "alice" &&
    test_result "output contains existing user name" "pass" ||
    test_result "output contains existing user name" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Test: user_remove
#==============================================================================

test_user_remove_by_name() {
  echo ""
  echo "Testing user_remove by name..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # Add a second user first so we can remove alice
  user_add --name "bob" >/dev/null 2>&1
  user_remove "alice" >/dev/null 2>&1

  local users
  users=$(_load_users 2>/dev/null) || true
  local found
  found=$(echo "${users}" | jq -r '.[] | select(.name == "alice") | .name' 2>/dev/null || true)
  local count
  count=$(echo "${users}" | jq 'length' 2>/dev/null || echo 0)

  [[ -z "${found}" ]] &&
    test_result "removes user by name" "pass" ||
    test_result "removes user by name (alice still present)" "fail"

  [[ "${count}" -eq 1 ]] &&
    test_result "count decrements after removal" "pass" ||
    test_result "count decrements after removal (count=${count})" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

test_user_remove_by_uuid() {
  echo ""
  echo "Testing user_remove by UUID..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # Add second user then remove alice by UUID
  user_add --name "bob" >/dev/null 2>&1
  user_remove "11111111-1111-1111-1111-111111111111" >/dev/null 2>&1

  local users found
  users=$(_load_users 2>/dev/null) || true
  found=$(echo "${users}" | jq -r '.[] | select(.uuid == "11111111-1111-1111-1111-111111111111") | .uuid' 2>/dev/null || true)

  [[ -z "${found}" ]] &&
    test_result "removes user by UUID" "pass" ||
    test_result "removes user by UUID (UUID still present)" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

test_user_remove_last_fails() {
  echo ""
  echo "Testing user_remove refuses to remove last user..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # Only alice exists — removal should fail
  user_remove "alice" >/dev/null 2>&1

  local users count
  users=$(_load_users 2>/dev/null) || true
  count=$(echo "${users}" | jq 'length' 2>/dev/null || echo 0)

  [[ "${count}" -eq 1 ]] &&
    test_result "refuses to remove last user" "pass" ||
    test_result "refuses to remove last user (count=${count})" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Test: user_reset
#==============================================================================

test_user_reset_changes_uuid() {
  echo ""
  echo "Testing user_reset regenerates UUID..."

  local tmp
  tmp=$(mktemp)
  _make_state_with_users "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  local old_uuid="11111111-1111-1111-1111-111111111111"
  user_reset "alice" >/dev/null 2>&1

  local users new_uuid name
  users=$(_load_users 2>/dev/null) || true
  new_uuid=$(echo "${users}" | jq -r '.[] | select(.name == "alice") | .uuid' 2>/dev/null || true)
  name=$(echo "${users}" | jq -r '.[] | select(.name == "alice") | .name' 2>/dev/null || true)

  [[ "${new_uuid}" != "${old_uuid}" && -n "${new_uuid}" ]] &&
    test_result "UUID changes after reset" "pass" ||
    test_result "UUID changes after reset (old=${old_uuid}, new=${new_uuid})" "fail"

  [[ "${name}" == "alice" ]] &&
    test_result "name is preserved after reset" "pass" ||
    test_result "name is preserved after reset (got '${name}')" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Test: _save_users / _load_users roundtrip
#==============================================================================

test_save_load_roundtrip() {
  echo ""
  echo "Testing _save_users / _load_users roundtrip..."

  local tmp
  tmp=$(mktemp)
  _make_legacy_state "${tmp}"
  export TEST_STATE_FILE="${tmp}"

  # Load (migrating from legacy), add a user, save, reload
  user_add --name "dave" >/dev/null 2>&1

  local users count dave_name
  users=$(_load_users 2>/dev/null) || true
  count=$(echo "${users}" | jq 'length' 2>/dev/null || echo 0)
  dave_name=$(echo "${users}" | jq -r '.[] | select(.name == "dave") | .name' 2>/dev/null || true)

  [[ "${count}" -eq 2 ]] &&
    test_result "state persists two users after add" "pass" ||
    test_result "state persists two users after add (count=${count})" "fail"

  [[ "${dave_name}" == "dave" ]] &&
    test_result "newly added user survives save/load" "pass" ||
    test_result "newly added user survives save/load (got '${dave_name}')" "fail"

  # Verify legacy uuid field updated to first user's UUID
  local top_uuid first_uuid
  top_uuid=$(jq -r '.protocols.reality.uuid' "${tmp}" 2>/dev/null || true)
  first_uuid=$(echo "${users}" | jq -r '.[0].uuid' 2>/dev/null || true)

  [[ "${top_uuid}" == "${first_uuid}" ]] &&
    test_result "legacy .protocols.reality.uuid stays in sync" "pass" ||
    test_result "legacy .protocols.reality.uuid stays in sync (top=${top_uuid}, first=${first_uuid})" "fail"

  unset TEST_STATE_FILE
  rm -f "${tmp}"
}

#==============================================================================
# Run All Tests
#==============================================================================

echo ""
echo "=========================================="
echo "Running test suite: lib/users.sh (User Management)"
echo "=========================================="

test_legacy_migration
test_user_add_generates_uuid
test_user_add_custom_name
test_user_add_auto_name
test_user_add_duplicate_name_fails
test_user_list_shows_table
test_user_remove_by_name
test_user_remove_by_uuid
test_user_remove_last_fails
test_user_reset_changes_uuid
test_save_load_roundtrip

echo ""
echo "=========================================="
echo "           Test Summary"
echo "=========================================="
echo "Total tests:  $TESTS_RUN"
echo "Passed:       $TESTS_PASSED"
echo "Failed:       $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All tests passed!"
  exit 0
else
  echo ""
  echo "✗ Some tests failed"
  exit 1
fi
