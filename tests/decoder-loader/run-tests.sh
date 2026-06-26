#!/usr/bin/env bash
# Week 1 smoke test for the MMProtect PHP Decoder/Loader.
# Creates a synthetic MMENC1 fixture (no license server required) and verifies
# the full encrypt → decrypt pipeline.
#
# Usage:
#   cd <repo-root>
#   tests/decoder-loader/run-tests.sh [path-to-mmloader.so]
#
# Prerequisites:
#   - php8.4 in PATH
#   - python3 + cryptography   (pip install cryptography)
#   - mmloader.so in artifacts/ (scripts/linux/build-decoder.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
FIXTURE_DIR="$(mktemp -d /tmp/mmenc1-test-XXXXXX)"
PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

echo "=== MMLoader Week-1 Smoke Tests ==="
echo "  Extension : $EXT"
echo "  PHP       : $(php8.4 --version | head -1)"
echo

if [[ ! -f "$EXT" ]]; then
    echo "ERROR: mmloader.so not found at $EXT"
    echo "  Run: scripts/linux/build-decoder.sh"
    exit 1
fi

# ---- Generate MMENC1 fixture ----
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

OUT        = sys.argv[1]
BUILD_ID   = "bld_test0001"
RELATIVE   = "src/hello.php"
FILE_ID    = "file_" + hashlib.sha256(RELATIVE.encode()).hexdigest()[:24]
PATH_HASH  = "sha256:" + hashlib.sha256(RELATIVE.encode()).hexdigest()
info       = f"{BUILD_ID}:{FILE_ID}:{PATH_HASH}".encode()
salt       = hashlib.sha256(b"MMProtect-HKDF-v1").digest()

build_key  = os.urandom(32)
file_key   = HKDF(SHA256(), 32, salt, info, default_backend()).derive(build_key)

plain_php  = b'<?php\necho "MMProtect Demo: protected project code executed\\n";\n'
nonce      = os.urandom(12)
ct_tag     = AESGCM(file_key).encrypt(nonce, plain_php, None)
ciphertext, tag = ct_tag[:-16], ct_tag[-16:]
cipher_hash = "sha256:" + hashlib.sha256(ciphertext).hexdigest()
sig_data    = f"{BUILD_ID}:{FILE_ID}:{cipher_hash}".encode()
signature   = base64.b64encode(hashlib.sha256(sig_data).digest()).decode()

header = {
    "algorithm": "AES-256-GCM", "buildId": BUILD_ID,
    "cipherHash": cipher_hash,
    "createdAt":  datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "customerId": "cust_test", "fileId": FILE_ID,
    "format": "MMENC1", "formatVersion": 1,
    "kdf": "HKDF-SHA256", "keyId": "dev", "licenseId": "lic_test",
    "manifestHash": "pending", "nonce": base64.b64encode(nonce).decode(),
    "pathHash": PATH_HASH,
    "plainHash": "sha256:" + hashlib.sha256(plain_php).hexdigest(),
    "projectId": "proj_test", "relativePath": RELATIVE,
    "signature": signature, "tag": base64.b64encode(tag).decode(),
}
hj = json.dumps(header, separators=(',', ':'), ensure_ascii=True).encode()
container = b"MMENC1\n" + f"{len(hj):08d}".encode() + b"\n" + hj + ciphertext

open(f"{OUT}/hello.php",        "wb").write(container)
open(f"{OUT}/dev-buildkey.b64", "w" ).write(base64.b64encode(build_key).decode() + "\n")
open(f"{OUT}/expected.txt",     "w" ).write("MMProtect Demo: protected project code executed\n")
PYEOF
echo "  Fixture: $FIXTURE_DIR"
echo

# ---- Test 1: Plain PHP file passes through ----
echo "Test 1: plain PHP passthrough"
PLAIN=$(mktemp /tmp/plain_XXXXXX.php)
printf '<?php echo "plain ok\n";' > "$PLAIN"
OUT1=$(php8.4 -d "extension=$EXT" "$PLAIN" 2>&1); rm -f "$PLAIN"
if [[ "$OUT1" == "plain ok" ]]; then
    ok "plain file executes normally"
else
    fail "plain file — expected 'plain ok', got: $OUT1"
fi

# ---- Test 2: MMENC1 decrypts and executes ----
echo "Test 2: MMENC1 decrypt + execute"
EXPECTED=$(cat "$FIXTURE_DIR/expected.txt")
ACTUAL=$(php8.4 -d "extension=$EXT" \
                -d "mmloader.dev_buildkey=$FIXTURE_DIR/dev-buildkey.b64" \
                "$FIXTURE_DIR/hello.php" 2>&1)
if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    ok "MMENC1 file decrypts and executes: $ACTUAL"
else
    fail "MMENC1 — expected '$EXPECTED', got '$ACTUAL'"
fi

# ---- Test 3: Wrong key produces AES-GCM auth failure ----
echo "Test 3: wrong key → AES-GCM auth failure"
WRONG_KEY=$(python3 -c "import base64,os; print(base64.b64encode(os.urandom(32)).decode())")
WRONG_KEY_FILE=$(mktemp /tmp/wrongkey_XXXXXX.b64)
echo "$WRONG_KEY" > "$WRONG_KEY_FILE"
ERR3=$(php8.4 -d "extension=$EXT" \
              -d "mmloader.dev_buildkey=$WRONG_KEY_FILE" \
              "$FIXTURE_DIR/hello.php" 2>&1 || true)
rm -f "$WRONG_KEY_FILE"
if echo "$ERR3" | grep -q "AES-GCM authentication failed\|failed to decrypt"; then
    ok "wrong key produces expected AES-GCM error"
else
    fail "wrong key — expected AES-GCM error, got: $ERR3"
fi

# ---- Test 4: Missing key file → error ----
echo "Test 4: missing key file → error"
ERR4=$(php8.4 -d "extension=$EXT" \
              -d "mmloader.dev_buildkey=/nonexistent/path/key.b64" \
              "$FIXTURE_DIR/hello.php" 2>&1 || true)
if echo "$ERR4" | grep -q "cannot open dev_buildkey\|failed to decrypt"; then
    ok "missing key file produces expected error"
else
    fail "missing key — expected error, got: $ERR4"
fi

# ---- Test 5: Disabled loader passes MMENC1 through (as raw text) ----
echo "Test 5: mmloader.enabled=0 → MMENC1 treated as plain text"
RAW=$(php8.4 -d "extension=$EXT" \
             -d "mmloader.enabled=0" \
             "$FIXTURE_DIR/hello.php" 2>&1)
if echo "$RAW" | grep -q "MMENC1"; then
    ok "disabled loader outputs raw MMENC1 bytes"
else
    fail "disabled loader — expected raw output, got: $RAW"
fi

# ---- Summary ----
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
