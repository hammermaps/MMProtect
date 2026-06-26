#!/usr/bin/env bash
# MMProtect End-to-End Integration Test
#
# Pipeline: encode → license server (SQLite) → encrypted PHP file
#           → mmloader → HTTP lease → decryption → PHP execution
#
# Tests both PHP 8.4 and PHP 8.5 if available.
#
# Usage:
#   tests/integration/run-integration-test.sh [--php84-ext PATH] [--php85-ext PATH]
#
# Prerequisites:
#   - dotnet 8 SDK
#   - php8.4-dev + php8.5-dev installed
#   - mmloader.so already built (scripts/linux/build-decoder.sh)
#   - openssl + python3 + cryptography pip package

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d /tmp/mmtest-integration-XXXXXX)"
KEY_DIR="$WORK_DIR/keys"
SQLITE_DB="$WORK_DIR/mm_license.db"
SERVER_LOG="$WORK_DIR/server.log"
SERVER_PID=""
SERVER_PORT=15380
PASS=0; FAIL=0

# Configurable extension paths
EXT84="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
EXT85="${2:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader-php85.so}"

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

stop_server() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    sleep 0.3
}
cleanup() {
    stop_server
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "========================================================"
echo " MMProtect End-to-End Integration Test"
echo "========================================================"
echo "  Repo    : $REPO_ROOT"
echo "  Work    : $WORK_DIR"
echo "  Ext 8.4 : $EXT84"
echo "  Ext 8.5 : $EXT85"
echo

# ---- Prerequisites check ----
for cmd in dotnet php8.4 openssl sqlite3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found in PATH" >&2; exit 1
    fi
done

# ---- Step 1: Generate ECDSA-P256 signing keys ----
echo "Step 1: Generating ECDSA-P256 signing keys..."
mkdir -p "$KEY_DIR"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$KEY_DIR/signing-private.pem" 2>/dev/null
openssl pkey   -in "$KEY_DIR/signing-private.pem" -pubout -out "$KEY_DIR/signing-public.pem"
chmod 600 "$KEY_DIR/signing-private.pem"
echo "  OK — keys in $KEY_DIR/"

# ---- Step 2: Create SQLite database ----
echo "Step 2: Initialising SQLite database..."
sqlite3 "$SQLITE_DB" < "$REPO_ROOT/database/sqlite/schema.sql"
echo "  OK — $SQLITE_DB"

# ---- Step 3: Build LicenseServer if needed ----
echo "Step 3: Building LicenseServer..."
dotnet build -c Release "$REPO_ROOT/src/LicenseServer/LicenseServer.csproj" -nologo -v q 2>&1 | tail -3

# ---- Step 4: Start LicenseServer with SQLite ----
echo "Step 4: Starting LicenseServer (SQLite mode, port $SERVER_PORT)..."
SERVER_EXE="$REPO_ROOT/src/LicenseServer/bin/Release/net8.0/MmProtect.LicenseServer.dll"
# contentRoot must point to the DLL directory so appsettings.json (API keys) is found.
SERVER_CONTENT="$(dirname "$(realpath "$SERVER_EXE")")"

ASPNETCORE_ENVIRONMENT=Integration \
ASPNETCORE_URLS="http://127.0.0.1:$SERVER_PORT" \
dotnet "$SERVER_EXE" \
    --contentRoot "$SERVER_CONTENT" \
    --DatabaseProvider sqlite \
    --ConnectionStrings:Sqlite "Data Source=$SQLITE_DB" \
    --Security:SigningPrivateKeyFile "$KEY_DIR/signing-private.pem" \
    --Security:LeaseTtlMinutes 60 \
    --Security:GracePeriodDays 3 \
    >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# Wait for server to start
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$SERVER_PORT/health" &>/dev/null; then
        break
    fi
    sleep 0.3
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "ERROR: Server exited. Log:" >&2
        cat "$SERVER_LOG" >&2
        exit 1
    fi
done
HEALTH=$(curl -sf "http://127.0.0.1:$SERVER_PORT/health" 2>/dev/null || echo "DOWN")
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "  OK — server running (PID $SERVER_PID)"
else
    echo "ERROR: health check failed: $HEALTH" >&2
    cat "$SERVER_LOG" >&2
    exit 1
fi

# ---- Step 5: Prepare demo project ----
echo "Step 5: Preparing demo project..."
DEMO_SRC="$REPO_ROOT/tests/php-demo"
# Ensure composer autoload exists
if [ ! -f "$DEMO_SRC/vendor/autoload.php" ]; then
    echo "  Running composer dump-autoload..."
    (cd "$DEMO_SRC" && composer dump-autoload -o -a -q 2>/dev/null) || true
fi

# ---- Step 6: Generate encoder config from template ----
echo "Step 6: Generating encoder config..."
OUTPUT_ROOT="$WORK_DIR/encoded"
mkdir -p "$OUTPUT_ROOT"
sed \
    -e "s|__SIGNING_PRIV__|$KEY_DIR/signing-private.pem|g" \
    -e "s|__SIGNING_PUB__|$KEY_DIR/signing-public.pem|g" \
    -e "s|__SOURCE_ROOT__|$DEMO_SRC|g" \
    -e "s|__OUTPUT_ROOT__|$OUTPUT_ROOT|g" \
    "$REPO_ROOT/tests/integration/encoder.config.integration.json" \
    > "$WORK_DIR/encoder.config.json"
echo "  OK"

# ---- Step 7: Run Encoder ----
echo "Step 7: Running Encoder..."
dotnet build -c Release "$REPO_ROOT/src/EncoderCli/EncoderCli.csproj" -nologo -v q 2>&1 | tail -3
MM_ENCODER_API_KEY="dev-encoder-api-key-change-me" \
dotnet run --project "$REPO_ROOT/src/EncoderCli/EncoderCli.csproj" -c Release --no-build -- \
    encode --config "$WORK_DIR/encoder.config.json" --project integration-test 2>&1 | tail -5

if [ -f "$OUTPUT_ROOT/.mmprotect/manifest.json" ] && [ -f "$OUTPUT_ROOT/.mmprotect/license.json" ]; then
    ok "Encoder produced manifest.json and license.json"
else
    fail "Encoder output missing .mmprotect files"
fi

# Count encrypted PHP files
ENC_COUNT=$(find "$OUTPUT_ROOT" -name "*.php" -not -path "*/.mmprotect/*" -not -path "*/vendor/*" -not -path "*/public/*" | wc -l | tr -d ' ')
DEV_KEY="$OUTPUT_ROOT/.mmprotect/dev-buildkey.b64"
if [ "$ENC_COUNT" -gt 0 ]; then
    ok "Encoder produced $ENC_COUNT encrypted PHP file(s)"
else
    fail "No encrypted PHP files found in output"
fi

# Verify first encoded file starts with MMENC1 magic
FIRST_ENC=$(find "$OUTPUT_ROOT/src" -name "*.php" | head -1)
if [ -n "$FIRST_ENC" ] && head -c 6 "$FIRST_ENC" | grep -q "MMENC1"; then
    ok "Encrypted file has MMENC1 magic header: $(basename "$FIRST_ENC")"
else
    fail "Encrypted file missing MMENC1 magic"
fi

# ---- Step 8: Test execution with PHP 8.4 (dev_mode, no HTTP) ----
echo "Step 8: Testing PHP 8.4 execution (dev_mode with dev-buildkey.b64)..."
if [ ! -f "$EXT84" ]; then
    echo "  SKIP — mmloader.so not found at $EXT84 (run scripts/linux/build-decoder.sh first)"
    FAIL=$((FAIL + 1))
else
    CACHE84="$WORK_DIR/cache84"
    mkdir -p "$CACHE84"
    RESULT84=$(php8.4 \
        -d "extension=$EXT84" \
        -d "mmloader.dev_buildkey=$DEV_KEY" \
        -d "mmloader.dev_mode=1" \
        -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
        -d "mmloader.cache_dir=$CACHE84" \
        "$OUTPUT_ROOT/public/index.php" 2>&1) || true
    if echo "$RESULT84" | grep -qi "MMProtect Demo"; then
        ok "PHP 8.4 dev_mode execution: $RESULT84"
    else
        fail "PHP 8.4 dev_mode execution failed: $RESULT84"
    fi
fi

# ---- Step 9: Test execution with PHP 8.4 (live HTTP lease from server) ----
echo "Step 9: Testing PHP 8.4 execution (live HTTP lease from license server)..."
if [ ! -f "$EXT84" ]; then
    echo "  SKIP — mmloader.so not found"
    FAIL=$((FAIL + 1))
else
    CACHE84_LIVE="$WORK_DIR/cache84live"
    mkdir -p "$CACHE84_LIVE"
    RESULT84L=$(php8.4 \
        -d "extension=$EXT84" \
        -d "mmloader.license_server=http://127.0.0.1:$SERVER_PORT" \
        -d "mmloader.manifest_file=$OUTPUT_ROOT/.mmprotect/manifest.json" \
        -d "mmloader.license_file=$OUTPUT_ROOT/.mmprotect/license.json" \
        -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
        -d "mmloader.dev_mode=1" \
        -d "mmloader.cache_dir=$CACHE84_LIVE" \
        "$OUTPUT_ROOT/public/index.php" 2>&1) || true
    if echo "$RESULT84L" | grep -qi "MMProtect Demo"; then
        ok "PHP 8.4 live-lease execution: $RESULT84L"
    else
        fail "PHP 8.4 live-lease execution failed: $RESULT84L"
    fi
fi

# ---- Step 10: Verify lease was stored in SQLite ----
echo "Step 10: Verifying lease record in SQLite..."
LEASE_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM runtime_leases;" 2>/dev/null || echo "0")
if [ "$LEASE_COUNT" -gt 0 ]; then
    ok "SQLite contains $LEASE_COUNT runtime lease(s) from live execution"
else
    fail "No lease records found in SQLite (live execution may have used cache)"
fi

# Also check activations
ACT_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM license_activations;" 2>/dev/null || echo "0")
BUILD_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM builds;" 2>/dev/null || echo "0")
echo "  DB stats: builds=$BUILD_COUNT, activations=$ACT_COUNT, leases=$LEASE_COUNT"

# ---- Step 11: Test PHP 8.5 if extension available ----
echo "Step 11: Testing PHP 8.5..."
if ! command -v php8.5 &>/dev/null; then
    echo "  SKIP — php8.5 not in PATH"
elif [ ! -f "$EXT85" ]; then
    echo "  SKIP — mmloader-php85.so not found at $EXT85 (run scripts/linux/build-decoder-php85.sh)"
else
    CACHE85="$WORK_DIR/cache85"
    mkdir -p "$CACHE85"
    RESULT85=$(php8.5 \
        -d "extension=$EXT85" \
        -d "mmloader.dev_buildkey=$DEV_KEY" \
        -d "mmloader.dev_mode=1" \
        -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
        -d "mmloader.cache_dir=$CACHE85" \
        "$OUTPUT_ROOT/public/index.php" 2>&1) || true
    if echo "$RESULT85" | grep -qi "MMProtect Demo"; then
        ok "PHP 8.5 dev_mode execution: $RESULT85"
    else
        fail "PHP 8.5 execution failed: $RESULT85"
    fi
fi

# ---- Step 12: OPcache test (PHP 8.4) ----
echo "Step 12: Testing with OPcache enabled (PHP 8.4)..."
if [ ! -f "$EXT84" ]; then
    echo "  SKIP — mmloader.so not found"
else
    CACHE_OPC="$WORK_DIR/cache_opc"
    mkdir -p "$CACHE_OPC"
    OPCACHE_SO=$(php8.4 -r "echo PHP_EXTENSION_DIR;" 2>/dev/null)/opcache.so
    if [ -f "$OPCACHE_SO" ]; then
        RESULT_OPC=$(php8.4 \
            -d "zend_extension=$OPCACHE_SO" \
            -d "opcache.enable=1" \
            -d "opcache.enable_cli=1" \
            -d "extension=$EXT84" \
            -d "mmloader.dev_buildkey=$DEV_KEY" \
            -d "mmloader.dev_mode=1" \
            -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
            -d "mmloader.cache_dir=$CACHE_OPC" \
            "$OUTPUT_ROOT/public/index.php" 2>&1) || true
        if echo "$RESULT_OPC" | grep -qi "MMProtect Demo"; then
            ok "OPcache+mmloader PHP 8.4 execution: $RESULT_OPC"
        else
            fail "OPcache+mmloader execution failed: $RESULT_OPC"
        fi
    else
        echo "  SKIP — opcache.so not found at $OPCACHE_SO"
    fi
fi

# ---- Summary ----
echo
echo "========================================================"
echo " Integration Test Results: $PASS passed, $FAIL failed"
echo "========================================================"
if [ $FAIL -eq 0 ]; then
    echo " ALL TESTS PASSED"
else
    echo " $FAIL TEST(S) FAILED"
    echo
    echo "Server log ($SERVER_LOG):"
    tail -20 "$SERVER_LOG" 2>/dev/null || true
fi
echo "========================================================"
[[ $FAIL -eq 0 ]]
