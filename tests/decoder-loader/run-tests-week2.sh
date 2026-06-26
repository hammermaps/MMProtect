#!/usr/bin/env bash
# Week 2 smoke tests for mmloader HTTP lease call.
# Spins up a Python mock license server, runs the loader against it,
# verifies the full cache→HTTP→decrypt pipeline.
#
# Prerequisites:
#   - php8.4 in PATH
#   - python3 + cryptography   (pip install cryptography)
#   - mmloader.so in artifacts/ (scripts/linux/build-decoder.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
FIXTURE_DIR="$(mktemp -d /tmp/mmenc2-test-XXXXXX)"
PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

SERVER_PID=""
stop_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""; sleep 0.2; }
cleanup()     { stop_server; rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

echo "=== MMLoader Week-2 HTTP Lease Tests ==="
echo "  Extension : $EXT"
echo "  PHP       : $(php8.4 --version | head -1)"
echo

if [[ ! -f "$EXT" ]]; then
    echo "ERROR: mmloader.so not found at $EXT"; echo "  Run: scripts/linux/build-decoder.sh"; exit 1
fi

# ---- Generate MMENC1 fixture, license.json, manifest.json ----
echo "  Generating fixture..."
python3 "$REPO_ROOT/tests/decoder-loader/make-week2-fixture.py" "$FIXTURE_DIR"
echo "  Fixture: $FIXTURE_DIR"
echo

BUILD_KEY_B64=$(cat "$FIXTURE_DIR/build_key_b64.txt")
EXPECTED=$(cat "$FIXTURE_DIR/expected.txt")

# Write re-usable mock server scripts to temp files ---
MOCK_OK_PY=$(mktemp /tmp/mock_ok_XXXXXX.py)
MOCK_403_PY=$(mktemp /tmp/mock_403_XXXXXX.py)
cat > "$MOCK_OK_PY" << 'PYEOF'
import sys, json, datetime, http.server, hmac as _hmac, hashlib, base64

build_key_b64, port = sys.argv[1], int(sys.argv[2])
# Signing key matches CryptoService.DemoSigningKey: SHA-256("mmprotect-dev-signing-key")
_signing_key = hashlib.sha256(b"mmprotect-dev-signing-key").digest()

def _sign(lease_id, build_id, machine_fp, expires_at_str):
    data = f"{lease_id}:{build_id}:{machine_fp}:{expires_at_str}".encode()
    return base64.b64encode(_hmac.new(_signing_key, data, hashlib.sha256).digest()).decode()

class OkHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): pass
    def do_POST(self):
        if self.path != "/api/v1/runtime/lease":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(length))
        build_id   = req.get("buildId", "")
        machine_fp = req.get("machineFingerprint", "")
        lease_id   = "lease_ok"
        g = (datetime.datetime.utcnow() + datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        resp = {
            "format": "MMENC-LEASE-1", "leaseId": lease_id,
            "projectId": req.get("projectId", ""), "customerId": req.get("customerId", ""),
            "licenseId": req.get("licenseId", ""), "buildId": build_id,
            "keyId": "key_w2", "runtimeKey": build_key_b64,
            "issuedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S+00:00"),
            "expiresAt": g, "graceUntil": g,
            "signature": _sign(lease_id, build_id, machine_fp, g),
        }
        data = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(data))
        self.end_headers()
        self.wfile.write(data)

http.server.HTTPServer(("127.0.0.1", port), OkHandler).serve_forever()
PYEOF

cat > "$MOCK_403_PY" << 'PYEOF'
import sys, http.server

class DenyHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): pass
    def do_POST(self): self.send_response(403); self.end_headers()

http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), DenyHandler).serve_forever()
PYEOF

start_ok_server() {
    stop_server
    python3 "$MOCK_OK_PY" "$BUILD_KEY_B64" 19876 &
    SERVER_PID=$!
    sleep 0.35
}

start_403_server() {
    stop_server
    python3 "$MOCK_403_PY" 19876 &
    SERVER_PID=$!
    sleep 0.3
}

INI=(
    -d "extension=$EXT"
    -d "mmloader.license_server=http://127.0.0.1:19876"
    -d "mmloader.manifest_file=$FIXTURE_DIR/.mmprotect/manifest.json"
    -d "mmloader.license_file=$FIXTURE_DIR/.mmprotect/license.json"
    -d "mmloader.dev_mode=1"
)

# ---- Test 1: HTTP lease call decrypts and executes ----
echo "Test 1: HTTP lease → decrypt + execute"
start_ok_server
ACTUAL=$(php8.4 "${INI[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    ok "HTTP lease resolves runtime key and decrypts file: $ACTUAL"
else
    fail "HTTP lease — expected '$EXPECTED', got '$ACTUAL'"
fi

# ---- Test 2: Per-process cache — two requires in one PHP process ----
echo "Test 2: per-process cache — two require calls, one HTTP call"
# Server is still up from Test 1
TWO=$(mktemp /tmp/two_req_XXXXXX.php)
printf '<?php require "%s/hello.php"; require "%s/hello.php";' "$FIXTURE_DIR" "$FIXTURE_DIR" > "$TWO"
OUT2=$(php8.4 "${INI[@]}" "$TWO" 2>&1); rm -f "$TWO"
COUNT2=$(echo "$OUT2" | grep -c "HTTP lease resolved" 2>/dev/null || true)
if [[ "$COUNT2" -ge 2 ]]; then
    ok "file executed twice (cache hit on second call)"
else
    fail "two-require test — expected 2 output lines, got: $OUT2"
fi

# ---- Test 3: Server returns 403 → fall back to dev_buildkey ----
echo "Test 3: server 403 → fallback to dev_buildkey"
start_403_server
DEVKEY=$(mktemp /tmp/fallback_XXXXXX.b64)
echo "$BUILD_KEY_B64" > "$DEVKEY"
ACTUAL3=$(php8.4 "${INI[@]}" -d "mmloader.dev_buildkey=$DEVKEY" "$FIXTURE_DIR/hello.php" 2>&1)
rm -f "$DEVKEY"
if echo "$ACTUAL3" | grep -qF "$EXPECTED"; then
    ok "server 403 + dev_buildkey fallback works (warnings expected)"
else
    fail "fallback test — expected output to contain '$EXPECTED', got: $ACTUAL3"
fi

# ---- Test 4: Server unreachable → fallback to dev_buildkey ----
echo "Test 4: server unreachable → fallback to dev_buildkey"
stop_server   # nothing listening on 19876
DEVKEY2=$(mktemp /tmp/fallback2_XXXXXX.b64)
echo "$BUILD_KEY_B64" > "$DEVKEY2"
ACTUAL4=$(php8.4 \
    -d "extension=$EXT" \
    -d "mmloader.license_server=http://127.0.0.1:19876" \
    -d "mmloader.manifest_file=$FIXTURE_DIR/.mmprotect/manifest.json" \
    -d "mmloader.license_file=$FIXTURE_DIR/.mmprotect/license.json" \
    -d "mmloader.dev_buildkey=$DEVKEY2" \
    -d "mmloader.dev_mode=1" \
    -d "mmloader.connect_timeout_ms=400" \
    -d "mmloader.request_timeout_ms=400" \
    "$FIXTURE_DIR/hello.php" 2>&1)
rm -f "$DEVKEY2"
if echo "$ACTUAL4" | grep -qF "$EXPECTED"; then
    ok "unreachable server + dev_buildkey fallback works (warnings expected)"
else
    fail "unreachable server — expected output to contain '$EXPECTED', got: $ACTUAL4"
fi

# ---- Test 5: No server + no dev_buildkey → compile error ----
echo "Test 5: no server, no dev_buildkey → compile error"
ERR5=$(php8.4 \
    -d "extension=$EXT" \
    -d "mmloader.manifest_file=$FIXTURE_DIR/.mmprotect/manifest.json" \
    -d "mmloader.license_file=$FIXTURE_DIR/.mmprotect/license.json" \
    "$FIXTURE_DIR/hello.php" 2>&1 || true)
if echo "$ERR5" | grep -q "no runtime key available\|failed to decrypt"; then
    ok "no-key-anywhere produces expected compile error"
else
    fail "no-key — expected compile error, got: $ERR5"
fi

rm -f "$MOCK_OK_PY" "$MOCK_403_PY"

# ---- Summary ----
echo
echo "=== Week-2 Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
