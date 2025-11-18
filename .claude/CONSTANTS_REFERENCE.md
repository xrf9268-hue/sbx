# Constants Reference

All constants defined in `lib/common.sh` and available globally after module loading.

## Quick Lookup by Category

### Certificate Management
- `CERT_EXPIRY_WARNING_DAYS=30` - Days before expiry to show warning
- `CERT_EXPIRY_WARNING_SEC=2592000` - Seconds (30 days) for openssl -checkend

### Cryptographic Validation
- `X25519_KEY_MIN_LENGTH=42` - Minimum X25519 key length (base64url)
- `X25519_KEY_MAX_LENGTH=44` - Maximum X25519 key length (base64url)
- `X25519_KEY_BYTES=32` - X25519 key size in bytes

### Backup & Encryption
- `BACKUP_PASSWORD_RANDOM_BYTES=48` - Random bytes for password generation
- `BACKUP_PASSWORD_LENGTH=64` - Final password length (chars)
- `BACKUP_PASSWORD_MIN_LENGTH=32` - Minimum acceptable password length

### Caddy Configuration
- `CADDY_HTTP_PORT_DEFAULT=80` - Default HTTP port
- `CADDY_HTTPS_PORT_DEFAULT=8445` - Default HTTPS port (cert management)
- `CADDY_FALLBACK_PORT_DEFAULT=8080` - Fallback HTTP port
- `CADDY_STARTUP_WAIT_SEC=2` - Wait time after starting Caddy
- `CADDY_CERT_POLL_INTERVAL_SEC=3` - Poll interval for cert availability

### Network & Timeouts
- `NETWORK_TIMEOUT_SEC=5` - General network operation timeout
- `HTTP_DOWNLOAD_TIMEOUT_SEC=30` - Large file download timeout

### Logging & Monitoring
- `LOG_VIEW_MAX_LINES=10000` - Maximum log lines to display
- `LOG_VIEW_DEFAULT_HISTORY="5 minutes ago"` - Default log history window
- `LOG_ROTATION_CHECK_INTERVAL=100` - Check rotation every N writes

### File Validation
- `MIN_MODULE_FILE_SIZE_BYTES=100` - Minimum module file size
- `MIN_MANAGER_FILE_SIZE_BYTES=5000` - Minimum manager script size

## Helper Functions

### File Operations
- `get_file_size(file)` - Cross-platform file size in bytes
- `get_file_mtime(file)` - Cross-platform modification time (YYYY-MM-DD HH:MM:SS)

### Secure Temporary Files
- `create_temp_file(prefix)` - Create temp file with 600 permissions
- `create_temp_dir(prefix)` - Create temp directory with 700 permissions

### JSON Operations
- `json_parse(json, path)` - Parse JSON with jq/python fallback
- `json_build(key, value)` - Build JSON with fallback

### Cryptographic Operations
- `crypto_random_hex(bytes)` - Generate random hex string (openssl → /dev/urandom)
- `crypto_sha256(file)` - Calculate SHA256 hash (openssl → shasum)

## Best Practices

**When to create a constant:**
- Magic number appears 2+ times
- Value has semantic meaning (timeout, limit, size)
- Value might need tuning/configuration
- Value is security-critical (password length, key size)

**Where to define:**
- `lib/common.sh` - Global constants used across modules
- `install_multi.sh (early)` - Boot-time constants before module loading
- Module-specific - Only if truly module-internal

**Naming conventions:**
- Use `SCREAMING_SNAKE_CASE`
- Include units: `_SEC`, `_BYTES`, `_LENGTH`, `_DAYS`
- Group related: `BACKUP_PASSWORD_*`, `CADDY_*_PORT_DEFAULT`
- Make readonly: `declare -r CONSTANT_NAME=value`

**Example:**
```bash
# ❌ BAD: Magic number
sleep 5
password=$(openssl rand -base64 48 | head -c 64)

# ✅ GOOD: Named constant with clear intent
declare -r SERVICE_STARTUP_WAIT_SEC=5
password=$(openssl rand -base64 "$BACKUP_PASSWORD_RANDOM_BYTES" | head -c "$BACKUP_PASSWORD_LENGTH")
```
