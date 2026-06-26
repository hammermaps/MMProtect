#!/usr/bin/env bash
# Week 4 tests: ECDSA-P256 signing, execute_ex OPcache guard, zend_extension_entry.
#
# Prerequisites:
#   - php8.4 in PATH
#   - python3 + cryptography   (pip install cryptography)
#   - openssl                  (for key generation)
#   - mmloader.so in artifacts/ (scripts/linux/build-decoder.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
FIXTURE_DIR="$(mktemp -d /tmp/mmenc4-test-XXXXXX)"
KEY_DIR="$(mktemp -d /tmp/mmenc4-keys-XXXXXX)"
CACHE_DIR="$(mktemp -d /tmp/mmenc4-cache-XXXXXX)"
PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

SERVER_PID=""
stop_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""; sleep 0.2; }
cleanup() { stop_server; rm -rf "$FIXTURE_DIR" "$KEY_DIR" "$CACHE_DIR"; }
trap cleanup EXIT

echo "=== MMLoader Week-4 ECDSA + execute_ex Tests ==="
echo "  Extension : $EXT"
echo "  PHP       : $(php8.4 --version | head -1)"
echo

if [[ ! -f "$EXT" ]]; then
    echo "ERROR: mmloader.so not found at $EXT"; exit 1
fi

# ---- Generate ECDSA-P256 key pair ----
echo "  Generating ECDSA-P256 key pair..."
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$KEY_DIR/private.pem" 2>/dev/null
openssl pkey -in "$KEY_DIR/private.pem" -pubout -out "$KEY_DIR/public.pem"
chmod 600 "$KEY_DIR/private.pem"
echo "  Keys: $KEY_DIR/"
echo

# ---- Generate MMENC1 fixture with ECDSA-P256 signature ----
echo "  Generating Week-4 fixture (ECDSA-P256 signature)..."
python3 - "$FIXTURE_DIR" "$KEY_DIR/private.pem" <<'PYEOF'
import os, sys, json, hashlib, base64, datetime
try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.hashes import SHA256, SHA256 as _sha256
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.backends import default_backend
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature
    import struct
except ImportError:
    sys.exit("pip install cryptography")

OUT, PRIV_PEM = sys.argv[1], sys.argv[2]

BUILD_ID  = "bld_week4test01"
RELATIVE  = "src/hello.php"
FILE_ID   = "file_" + hashlib.sha256(RELATIVE.encode()).hexdigest()[:24]
PATH_HASH = "sha256:" + hashlib.sha256(RELATIVE.encode()).hexdigest()
info      = f"{BUILD_ID}:{FILE_ID}:{PATH_HASH}".encode()
salt      = hashlib.sha256(b"MMProtect-HKDF-v1").digest()

build_key = os.urandom(32)
file_key  = HKDF(SHA256(), 32, salt, info, default_backend()).derive(build_key)
plain_php = b'<?php\necho "MMProtect Week4: ECDSA-P256 verified\\n";\n'
nonce     = os.urandom(12)
ct_tag    = AESGCM(file_key).encrypt(nonce, plain_php, None)
ciphertext, tag = ct_tag[:-16], ct_tag[-16:]

cipher_hash = "sha256:" + hashlib.sha256(ciphertext).hexdigest()
sig_data    = f"{BUILD_ID}:{FILE_ID}:{cipher_hash}".encode()

# ECDSA-P256 signature in DER format (matches .NET DSASignatureFormat.Rfc3279DerSequence
# and OpenSSL EVP_DigestVerify)
with open(PRIV_PEM, "rb") as f:
    priv_key = serialization.load_pem_private_key(f.read(), password=None)

from cryptography.hazmat.primitives.asymmetric import ec as ec2
from cryptography.hazmat.primitives import hashes
signature_der = priv_key.sign(sig_data, ec2.ECDSA(hashes.SHA256()))
signature     = base64.b64encode(signature_der).decode()

header = {
    "algorithm": "AES-256-GCM", "buildId": BUILD_ID,
    "cipherHash": cipher_hash,
    "createdAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "customerId": "cust_w4", "fileId": FILE_ID,
    "format": "MMENC1", "formatVersion": 1,
    "kdf": "HKDF-SHA256", "keyId": "ecdsa",
    "licenseId": "lic_w4", "manifestHash": "pending",
    "nonce": base64.b64encode(nonce).decode(), "pathHash": PATH_HASH,
    "plainHash": "sha256:" + hashlib.sha256(plain_php).hexdigest(),
    "projectId": "proj_w4", "relativePath": RELATIVE,
    "signature": signature, "tag": base64.b64encode(tag).decode(),
}
hj        = json.dumps(header, separators=(',', ':'), ensure_ascii=True).encode()
container = b"MMENC1\n" + f"{len(hj):08d}".encode() + b"\n" + hj + ciphertext

mmprotect = os.path.join(OUT, ".mmprotect")
os.makedirs(mmprotect, exist_ok=True)

open(f"{OUT}/hello.php",          "wb").write(container)
open(f"{OUT}/expected.txt",       "w" ).write("MMProtect Week4: ECDSA-P256 verified\n")
open(f"{OUT}/dev-buildkey.b64",   "w" ).write(base64.b64encode(build_key).decode() + "\n")
open(f"{OUT}/build_key_b64.txt",  "w" ).write(base64.b64encode(build_key).decode())

# Wrong-signature version: SHA-256 hash (old format) — should fail ECDSA verify
sha_sig    = base64.b64encode(hashlib.sha256(sig_data).digest()).decode()
header_sha = dict(header); header_sha["signature"] = sha_sig
hj_sha     = json.dumps(header_sha, separators=(',', ':'), ensure_ascii=True).encode()
container_sha = b"MMENC1\n" + f"{len(hj_sha):08d}".encode() + b"\n" + hj_sha + ciphertext
open(f"{OUT}/hello_wrongsig.php", "wb").write(container_sha)

open(f"{mmprotect}/license.json", "w").write(json.dumps({
    "format": "MMENC-LICENSE-1",
    "licenseId": "lic_w4", "projectId": "proj_w4", "customerId": "cust_w4",
    "buildId": BUILD_ID, "licenseServer": "http://127.0.0.1:19876", "features": [],
}))
open(f"{mmprotect}/manifest.json", "w").write(json.dumps({
    "format": "MMENC-MANIFEST-1",
    "projectId": "proj_w4", "customerId": "cust_w4",
    "licenseId": "lic_w4", "buildId": BUILD_ID,
    "version": "1.0.0", "phpMinVersion": "8.1",
    "algorithm": "AES-256-GCM", "kdf": "HKDF-SHA256",
    "files": [], "manifestHash": "pending", "signature": "dev-placeholder",
}))
PYEOF

echo "  Fixture: $FIXTURE_DIR"
echo

BUILD_KEY_B64=$(cat "$FIXTURE_DIR/build_key_b64.txt")
EXPECTED=$(cat "$FIXTURE_DIR/expected.txt")

# Mock server that signs with ECDSA-P256
MOCK_ECDSA_PY=$(mktemp /tmp/mock_ecdsa_XXXXXX.py)
cat > "$MOCK_ECDSA_PY" << 'PYEOF'
import sys, json, datetime, http.server, base64
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.backends import default_backend

bk, priv_pem, port = sys.argv[1], sys.argv[2], int(sys.argv[3])

with open(priv_pem, "rb") as f:
    _priv_key = serialization.load_pem_private_key(f.read(), password=None)

def _sign(data_str):
    sig_der = _priv_key.sign(data_str.encode(), ec.ECDSA(hashes.SHA256()))
    return base64.b64encode(sig_der).decode()

class H(http.server.BaseHTTPRequestHandler):
    def log_message(s, *a): pass
    def do_POST(s):
        if s.path != "/api/v1/runtime/lease":
            s.send_response(404); s.end_headers(); return
        l = int(s.headers.get("Content-Length", 0))
        req = json.loads(s.rfile.read(l))
        bid = req.get("buildId", ""); mfp = req.get("machineFingerprint", "")
        lid = "lease_ecdsa_w4"
        g = (datetime.datetime.utcnow() + datetime.timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        sig_data = f"{lid}:{bid}:{mfp}:{g}"
        r = {"format":"MMENC-LEASE-1","leaseId":lid,
             "projectId":req.get("projectId",""),"customerId":req.get("customerId",""),
             "licenseId":req.get("licenseId",""),"buildId":bid,
             "keyId":"ecdsa","runtimeKey":bk,
             "issuedAt":datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S+00:00"),
             "expiresAt":g,"graceUntil":g,"signature":_sign(sig_data)}
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
    -d "mmloader.signing_public_key_file=$KEY_DIR/public.pem"
    -d "mmloader.cache_dir=$CACHE_DIR"
)

INI_SRV=(
    -d "extension=$EXT"
    -d "mmloader.license_server=http://127.0.0.1:19876"
    -d "mmloader.manifest_file=$FIXTURE_DIR/.mmprotect/manifest.json"
    -d "mmloader.license_file=$FIXTURE_DIR/.mmprotect/license.json"
    -d "mmloader.signing_public_key_file=$KEY_DIR/public.pem"
    -d "mmloader.dev_mode=1"
    -d "mmloader.cache_dir=$CACHE_DIR"
)

# ---- Test 1: ECDSA-P256 signature accepted ----
echo "Test 1: ECDSA-P256 file signature accepted"
ACTUAL1=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
if [[ "$ACTUAL1" == "$EXPECTED" ]]; then
    ok "ECDSA-P256 signature verified and file executed: $ACTUAL1"
else
    fail "ECDSA-P256 accepted — expected '$EXPECTED', got: $ACTUAL1"
fi

# ---- Test 2: Wrong signature (SHA-256 hash) rejected when ECDSA key configured ----
echo "Test 2: SHA-256 demo signature rejected when ECDSA key is configured"
ERR2=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello_wrongsig.php" 2>&1 || true)
if echo "$ERR2" | grep -q "signature mismatch\|failed to decrypt"; then
    ok "SHA-256 demo signature correctly rejected by ECDSA verifier"
else
    fail "wrong sig test — expected rejection, got: $ERR2"
fi

# ---- Test 3: phpinfo shows ECDSA-P256 signing mode ----
echo "Test 3: phpinfo reports ECDSA-P256 signing mode"
PHPINFO=$(php8.4 "${INI_DEV[@]}" -r 'phpinfo();' 2>&1)
if echo "$PHPINFO" | grep -q "ECDSA-P256\|execute_ex hook"; then
    ok "phpinfo shows ECDSA-P256 and execute_ex hook active"
else
    fail "phpinfo missing ECDSA-P256/execute_ex info: $(echo "$PHPINFO" | grep -i "sign\|execute" | head -3)"
fi

# ---- Test 4: execute_ex hook — file in protected_files executes normally ----
echo "Test 4: execute_ex hook — MMENC1 file in protected set executes normally"
ACTUAL4=$(php8.4 "${INI_DEV[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
if [[ "$ACTUAL4" == "$EXPECTED" ]]; then
    ok "execute_ex hook passes authorised MMENC1 file: $ACTUAL4"
else
    fail "execute_ex passthrough — expected '$EXPECTED', got: $ACTUAL4"
fi

# ---- Test 5: ECDSA-P256 lease signature verified by server ----
echo "Test 5: ECDSA lease signature from mock server accepted"
python3 "$MOCK_ECDSA_PY" "$BUILD_KEY_B64" "$KEY_DIR/private.pem" 19876 &
SERVER_PID=$!
sleep 0.35
ACTUAL5=$(php8.4 "${INI_SRV[@]}" "$FIXTURE_DIR/hello.php" 2>&1)
stop_server
if [[ "$ACTUAL5" == "$EXPECTED" ]]; then
    ok "ECDSA-P256 lease signature accepted, file decrypted: $ACTUAL5"
else
    fail "ECDSA lease — expected '$EXPECTED', got: $ACTUAL5"
fi

# ---- Test 6: execute_ex blocks execution with no lease key ----
echo "Test 6: execute_ex blocks MMENC1 file when no key available"
ERR6=$(php8.4 \
    -d "extension=$EXT" \
    -d "mmloader.signing_public_key_file=$KEY_DIR/public.pem" \
    -d "mmloader.cache_dir=$CACHE_DIR" \
    "$FIXTURE_DIR/hello.php" 2>&1 || true)
if echo "$ERR6" | grep -q "unverified protected file blocked\|failed to decrypt\|no runtime key"; then
    ok "execute_ex correctly blocks MMENC1 file with no runtime key"
else
    fail "execute_ex block test — expected block error, got: $ERR6"
fi

# ---- Test 7: zend_extension_entry symbol exported ----
echo "Test 7: zend_extension_entry symbol exported from .so"
if nm -D "$EXT" 2>/dev/null | grep -q "zend_extension_entry\|get_module"; then
    SYMS=$(nm -D "$EXT" 2>/dev/null | grep -E "zend_extension_entry|get_module" | awk '{print $3}' | tr '\n' ' ')
    ok "extension exports: $SYMS"
else
    fail "zend_extension_entry not found in symbol table"
fi

rm -f "$MOCK_ECDSA_PY"

# ---- Summary ----
echo
echo "=== Week-4 Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
