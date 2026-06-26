#!/usr/bin/env bash
# Week 3 smoke tests: machine fingerprint, file-sig verify, disk lease cache,
# offline grace logic, tampered signature detection.
#
# Prerequisites:
#   - php8.4 in PATH
#   - python3 + cryptography   (pip install cryptography)
#   - mmloader.so in artifacts/ (scripts/linux/build-decoder.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
FIXTURE_DIR="$(mktemp -d /tmp/mmenc3-test-XXXXXX)"
CACHE_DIR="$(mktemp -d /tmp/mmenc3-cache-XXXXXX)"
PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

SERVER_PID=""
stop_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""; sleep 0.2; }
cleanup()     { stop_server; rm -rf "$FIXTURE_DIR" "$CACHE_DIR"; }
trap cleanup EXIT

echo "=== MMLoader Week-3 Security Tests ==="
echo "  Extension : $EXT"
echo "  PHP       : $(php8.4 --version | head -1)"
echo

if [[ ! -f "$EXT" ]]; then
    echo "ERROR: mmloader.so not found at $EXT"; exit 1
fi

# ---- Generate MMENC1 fixture (correct SHA-256 signature) ----
echo "  Generating fixture..."
python3 - "$FIXTURE_DIR" <<'PYEOF'
import os, sys, json, hashlib, base64, datetime
try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.hashes import SHA256
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.backends import default_backend
except ImportError:
    sys.exit("pip install cryptography")

OUT       = sys.argv[1]
BUILD_ID  = "bld_week3test01"
RELATIVE  = "src/hello.php"
FILE_ID   = "file_" + hashlib.sha256(RELATIVE.encode()).hexdigest()[:24]
PATH_HASH = "sha256:" + hashlib.sha256(RELATIVE.encode()).hexdigest()
info      = f"{BUILD_ID}:{FILE_ID}:{PATH_HASH}".encode()
salt      = hashlib.sha256(b"MMProtect-HKDF-v1").digest()

build_key = os.urandom(32)
file_key  = HKDF(SHA256(), 32, salt, info, default_backend()).derive(build_key)
plain_php = b'<?php\necho "MMProtect Week3: security gates active\\n";\n'
nonce     = os.urandom(12)
ct_tag    = AESGCM(file_key).encrypt(nonce, plain_php, None)
ciphertext, tag = ct_tag[:-16], ct_tag[-16:]

cipher_hash = "sha256:" + hashlib.sha256(ciphertext).hexdigest()
sig_data    = f"{BUILD_ID}:{FILE_ID}:{cipher_hash}".encode()
signature   = base64.b64encode(hashlib.sha256(sig_data).digest()).decode()

header = {
    "algorithm": "AES-256-GCM", "buildId": BUILD_ID,
    "cipherHash": cipher_hash,
    "createdAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "customerId": "cust_w3", "fileId": FILE_ID,
    "format": "MMENC1", "formatVersion": 1,
    "kdf": "HKDF-SHA256", "keyId": "dev",
    "licenseId": "lic_w3", "manifestHash": "pending",
    "nonce": base64.b64encode(nonce).decode(), "pathHash": PATH_HASH,
    "plainHash": "sha256:" + hashlib.sha256(plain_php).hexdigest(),
    "projectId": "proj_w3", "relativePath": RELATIVE,
    "signature": signature, "tag": base64.b64encode(tag).decode(),
}
hj        = json.dumps(header, separators=(',', ':'), ensure_ascii=True).encode()
container = b"MMENC1\n" + f"{len(hj):08d}".encode() + b"\n" + hj + ciphertext

# Tampered version: flip one byte in ciphertext (signature still points to original)
ciphertext_tampered = bytearray(ciphertext)
ciphertext_tampered[0] ^= 0xFF
container_tampered = b"MMENC1\n" + f"{len(hj):08d}".encode() + b"\n" + hj + bytes(ciphertext_tampered)

# Wrong-signature version: valid ciphertext, signature covers wrong data
bad_sig_data = f"{BUILD_ID}:{FILE_ID}:sha256:badbeefcafe".encode()
bad_signature = base64.b64encode(hashlib.sha256(bad_sig_data).digest()).decode()
header_badsig = dict(header)
header_badsig["signature"] = bad_signature
hj_badsig = json.dumps(header_badsig, separators=(',', ':'), ensure_ascii=True).encode()
container_badsig = b"MMENC1\n" + f"{len(hj_badsig):08d}".encode() + b"\n" + hj_badsig + ciphertext

mmprotect = os.path.join(OUT, ".mmprotect")
os.makedirs(mmprotect, exist_ok=True)

open(f"{OUT}/hello.php",           "wb").write(container)
open(f"{OUT}/hello_tampered.php",  "wb").write(container_tampered)
open(f"{OUT}/hello_badsig.php",    "wb").write(container_badsig)
open(f"{OUT}/expected.txt",        "w" ).write("MMProtect Week3: security gates active\n")
open(f"{OUT}/dev-buildkey.b64",    "w" ).write(base64.b64encode(build_key).decode() + "\n")
open(f"{OUT}/build_key_b64.txt",   "w" ).write(base64.b64encode(build_key).decode())

open(f"{mmprotect}/license.json", "w").write(json.dumps({
    "format": "MMENC-LICENSE-1",
    "licenseId": "lic_w3", "projectId": "proj_w3", "customerId": "cust_w3",
    "buildId": BUILD_ID, "licenseServer": "http://127.0.0.1:19876", "features": [],
}))
open(f"{mmprotect}/manifest.json", "w").write(json.dumps({
    "format": "MMENC-MANIFEST-1",
    "projectId": "proj_w3", "customerId": "cust_w3",
    "licenseId": "lic_w3", "buildId": BUILD_ID,
    "version": "1.0.0", "phpMinVersion": "8.1",
    "algorithm": "AES-256-GCM", "kdf": "HKDF-SHA256",
    "files": [], "manifestHash": "pending", "signature": "dev-placeholder",
}))
PYEOF

echo "  Fixture: $FIXTURE_DIR"
echo "  Cache:   $CACHE_DIR"
echo

BUILD_KEY_B64=$(cat "$FIXTURE_DIR/build_key_b64.txt")
EXPECTED=$(cat "$FIXTURE_DIR/expected.txt")

MOCK_OK_PY=$(mktemp /tmp/mock_ok3_XXXXXX.py)
cat > "$MOCK_OK_PY" << 'PYEOF'
import sys, json, datetime, http.server, hmac as _hmac, hashlib, base64

bk, port = sys.argv[1], int(sys.argv[2])
_signing_key = hashlib.sha256(b"mmprotect-dev-signing-key").digest()

def _sign(lid, bid, mfp, exp):
    return base64.b64encode(_hmac.new(_signing_key,
        f"{lid}:{bid}:{mfp}:{exp}".encode(), hashlib.sha256).digest()).decode()

class H(http.server.BaseHTTPRequestHandler):
    def log_message(s, *a): pass
    def do_POST(s):
        if s.path != "/api/v1/runtime/lease":
            s.send_response(404); s.end_headers(); return
        l = int(s.headers.get("Content-Length", 0))
        req = json.loads(s.rfile.read(l))
        bid, mfp = req.get("buildId",""), req.get("machineFingerprint","")
        lid = "lease_ok_w3"
        g = (datetime.datetime.utcnow()+datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        r = {"format":"MMENC-LEASE-1","leaseId":lid,
             "projectId":req.get("projectId",""),"customerId":req.get("customerId",""),
             "licenseId":req.get("licenseId",""),"buildId":bid,
             "keyId":"key_w3","runtimeKey":bk,
             "issuedAt":datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S+00:00"),
             "expiresAt":g,"graceUntil":g,"signature":_sign(lid,bid,mfp,g)}
        d = json.dumps(r).encode()
        s.send_response(200)
        s.send_header("Content-Type","application/json")
        s.send_header("Content-Length",len(d)); s.end_headers(); s.wfile.write(d)

http.server.HTTPServer(("127.0.0.1",port),H).serve_forever()
PYEOF

INI_DEV=(
    -d "extension=$EXT"
    -d "mmloader.dev_buildkey=$FIXTURE_DIR/dev-buildkey.b64"
    -d "mmloader.dev_mode=1"
    -d "mmloader.cache_dir=$CACHE_DIR"
)

INI_SRV=(
    -d "extension=$EXT"
    -d "mmloader.license_server=http://127.0.0.1:19876"
    -d "mmloader.manifest_file=$FIXTURE_DIR/.mmprotect/manifest.json"
    -d "mmloader.license_file=$FIXTURE_DIR/.mmprotect/license.json"
    -d "mmloader.dev_mode=1"
    -d "mmloader.cache_dir=$CACHE_DIR"
)

# ---- Test 1: Correct SHA-256 signature passes verification ----
echo "Test 1: correct file signature accepted"
ACTUAL=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    ok "valid SHA-256 signature accepted: $ACTUAL"
else
    fail "valid signature — expected '$EXPECTED', got '$ACTUAL'"
fi

# ---- Test 2: Wrong signature → compile error (require_signature=1) ----
echo "Test 2: wrong file signature → compile error"
ERR2=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello_badsig.php" 2>&1 || true)
if echo "$ERR2" | grep -q "signature mismatch\|failed to decrypt"; then
    ok "bad signature blocked as expected"
else
    fail "bad signature — expected block, got: $ERR2"
fi

# ---- Test 3: Wrong signature ignored when require_signature=0 ----
echo "Test 3: wrong signature ignored when require_signature=0"
ACTUAL3=$(php8.4 "${INI_DEV[@]}" \
    -d "mmloader.require_signature=0" \
    "$FIXTURE_DIR/hello_badsig.php" 2>&1)
if echo "$ACTUAL3" | grep -qF "$EXPECTED"; then
    ok "require_signature=0 ignores bad signature"
else
    fail "require_signature=0 — expected execute, got: $ACTUAL3"
fi

# ---- Test 4: Tampered ciphertext → AES-GCM auth failure ----
echo "Test 4: tampered ciphertext → AES-GCM auth failure"
ERR4=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello_tampered.php" 2>&1 || true)
if echo "$ERR4" | grep -q "AES-GCM authentication failed\|failed to decrypt"; then
    ok "tampered ciphertext detected by AES-GCM"
else
    fail "tampered ciphertext — expected AES-GCM error, got: $ERR4"
fi

# ---- Test 5: Disk cache written after first HTTP lease call ----
echo "Test 5: disk cache written after first HTTP lease call"
python3 "$MOCK_OK_PY" "$BUILD_KEY_B64" 19876 &
SERVER_PID=$!
sleep 0.35

php8.4 "${INI_SRV[@]}" "$FIXTURE_DIR/hello.php" > /dev/null 2>&1 || true
CACHE_FILES=$(find "$CACHE_DIR" -name "*.lease" | wc -l)
stop_server
if [[ "$CACHE_FILES" -ge 1 ]]; then
    LEASE_FILE=$(find "$CACHE_DIR" -name "*.lease" | head -1)
    LEASE_CONTENTS=$(cat "$LEASE_FILE" 2>/dev/null || true)
    if echo "$LEASE_CONTENTS" | grep -q "buildId\|runtimeKey"; then
        ok "disk cache file created at $LEASE_FILE"
    else
        fail "disk cache file exists but has unexpected contents: $LEASE_CONTENTS"
    fi
else
    fail "no disk cache file written in $CACHE_DIR"
fi

# ---- Test 6: Offline grace — server down, disk cache used ----
echo "Test 6: offline grace — server down, disk cache serves key"
# Server is stopped. Disk cache exists from Test 5. graceUntil is 1h from now.
ACTUAL6=$(php8.4 "${INI_SRV[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
if echo "$ACTUAL6" | grep -qF "$EXPECTED"; then
    ok "disk cache used during grace period (offline mode)"
else
    fail "offline grace — expected '$EXPECTED', got: $ACTUAL6"
fi

# ---- Test 7: Machine fingerprint is non-empty hex string ----
echo "Test 7: machine fingerprint is non-empty 64-char hex"
FP=$(php8.4 -d "extension=$EXT" -r 'phpinfo();' 2>/dev/null | grep -i "fingerprint" || true)
if [[ -z "$FP" ]]; then
    # Alternate: check via a lease request body (fingerprint is logged in the request)
    TMPLOG=$(mktemp /tmp/fp_log_XXXXXX)
    python3 - 19876 "$TMPLOG" << 'PYEOF' &
import sys, json, http.server
port, logfile = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(s,*a): pass
    def do_POST(s):
        l = int(s.headers.get("Content-Length",0))
        req = json.loads(s.rfile.read(l))
        open(logfile,"w").write(req.get("machineFingerprint",""))
        s.send_response(200)
        s.send_header("Content-Type","application/json")
        s.send_header("Content-Length","2"); s.end_headers(); s.wfile.write(b"{}")
http.server.HTTPServer(("127.0.0.1",port),H).serve_forever()
PYEOF
    SERVER_PID=$!
    sleep 0.3
    php8.4 "${INI_SRV[@]}" "$FIXTURE_DIR/hello.php" > /dev/null 2>&1 || true
    stop_server
    FINGERPRINT=$(cat "$TMPLOG" 2>/dev/null || true)
    rm -f "$TMPLOG"
    if echo "$FINGERPRINT" | grep -qE '^[0-9a-f]{64}$'; then
        ok "machine fingerprint is 64-char hex: ${FINGERPRINT:0:16}..."
    else
        fail "machine fingerprint format invalid: '$FINGERPRINT'"
    fi
else
    ok "fingerprint visible in phpinfo"
fi

rm -f "$MOCK_OK_PY"

# ---- Summary ----
echo
echo "=== Week-3 Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
