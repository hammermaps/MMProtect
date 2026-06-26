#!/usr/bin/env python3
"""
Creates a valid MMENC1 fixture for Week-1 loader smoke testing.
No license server required — uses a locally generated build key.

Outputs:
  /tmp/mmenc1-test/             — directory with test files
  /tmp/mmenc1-test/hello.php   — encoded PHP file (MMENC1 format)
  /tmp/mmenc1-test/dev-buildkey.b64  — Base64 build key for the loader
  /tmp/mmenc1-test/expected.txt — expected PHP output for verification
"""
import os, sys, json, hashlib, base64, struct, datetime

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.hashes import SHA256
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.backends import default_backend
except ImportError:
    sys.exit("Install: pip install cryptography")

OUT = "/tmp/mmenc1-test"
os.makedirs(OUT, exist_ok=True)

# ---- Known identifiers (matching encoder's field format) ----
BUILD_ID    = "bld_test0001"
FILE_ID     = "file_" + hashlib.sha256(b"src/hello.php").hexdigest()[:24]
RELATIVE    = "src/hello.php"
PATH_HASH   = "sha256:" + hashlib.sha256(RELATIVE.encode()).hexdigest()
PROJECT_ID  = "proj_test"
CUSTOMER_ID = "cust_test"
LICENSE_ID  = "lic_test"

# ---- Build key (32 random bytes) ----
build_key = os.urandom(32)
build_key_b64 = base64.b64encode(build_key).decode()

# ---- Derive file key via HKDF-SHA256 ----
# Info: "buildId:fileId:pathHash" (pathHash includes "sha256:" prefix)
info = f"{BUILD_ID}:{FILE_ID}:{PATH_HASH}".encode()
salt = hashlib.sha256(b"MMProtect-HKDF-v1").digest()

hkdf = HKDF(algorithm=SHA256(), length=32, salt=salt, info=info,
            backend=default_backend())
file_key = hkdf.derive(build_key)

# ---- PHP plaintext to encrypt (full file including <?php) ----
plain_php = b'<?php\necho "MMProtect Demo: protected project code executed\\n";\n'
plain_hash = "sha256:" + hashlib.sha256(plain_php).hexdigest()

# ---- AES-256-GCM encrypt ----
nonce = os.urandom(12)
aesgcm = AESGCM(file_key)
ct_with_tag = aesgcm.encrypt(nonce, plain_php, None)  # no AAD
ciphertext = ct_with_tag[:-16]
tag        = ct_with_tag[-16:]

nonce_b64 = base64.b64encode(nonce).decode()
tag_b64   = base64.b64encode(tag).decode()
cipher_hash = "sha256:" + hashlib.sha256(ciphertext).hexdigest()
sig_data    = f"{BUILD_ID}:{FILE_ID}:{cipher_hash}".encode()
signature   = base64.b64encode(hashlib.sha256(sig_data).digest()).decode()

# ---- Build JSON header (camelCase, compact, sorted keys) ----
header_dict = {
    "algorithm":   "AES-256-GCM",
    "buildId":     BUILD_ID,
    "cipherHash":  cipher_hash,
    "createdAt":   datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "customerId":  CUSTOMER_ID,
    "fileId":      FILE_ID,
    "format":      "MMENC1",
    "formatVersion": 1,
    "kdf":         "HKDF-SHA256",
    "keyId":       "dev",
    "licenseId":   LICENSE_ID,
    "manifestHash": "pending",
    "nonce":       nonce_b64,
    "pathHash":    PATH_HASH,
    "plainHash":   plain_hash,
    "projectId":   PROJECT_ID,
    "relativePath": RELATIVE,
    "signature":   signature,
    "tag":         tag_b64,
}
# Keys already sorted alphabetically above (matches System.Text.Json camelCase)
header_json = json.dumps(header_dict, separators=(',', ':'), ensure_ascii=True).encode()
header_len_str = f"{len(header_json):08d}".encode()

# ---- Assemble MMENC1 container ----
container = b"MMENC1\n" + header_len_str + b"\n" + header_json + ciphertext

# ---- Write output files ----
encoded_path = os.path.join(OUT, "hello.php")
with open(encoded_path, "wb") as f:
    f.write(container)

key_path = os.path.join(OUT, "dev-buildkey.b64")
with open(key_path, "w") as f:
    f.write(build_key_b64 + "\n")

with open(os.path.join(OUT, "expected.txt"), "w") as f:
    f.write("MMProtect Demo: protected project code executed\n")

print(f"Fixture written to {OUT}/")
print(f"  hello.php     : {len(container)} bytes (MMENC1)")
print(f"  dev-buildkey.b64 : {build_key_b64}")
print(f"  Build ID      : {BUILD_ID}")
print(f"  File ID       : {FILE_ID}")
print(f"  Path hash     : {PATH_HASH}")
print(f"  HKDF info     : {info.decode()}")
print()
print("Run the smoke test:")
print(f"  php8.4 -d extension=<mmloader.so>")
print(f"         -d mmloader.dev_buildkey={key_path}")
print(f"         {encoded_path}")
