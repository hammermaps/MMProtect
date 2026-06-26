#!/usr/bin/env python3
"""
Creates MMENC1 fixture for Week-2 loader HTTP lease tests.
Outputs fixture dir with hello.php, .mmprotect/{license,manifest}.json,
expected.txt, and build_key_b64.txt (for the mock server).
Usage: make-week2-fixture.py <output-dir>
"""
import os, sys, json, hashlib, base64, datetime

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.hashes import SHA256
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.backends import default_backend
except ImportError:
    sys.exit("pip install cryptography")

OUT       = sys.argv[1]
BUILD_ID  = "bld_week2test01"
RELATIVE  = "src/hello.php"
FILE_ID   = "file_" + hashlib.sha256(RELATIVE.encode()).hexdigest()[:24]
PATH_HASH = "sha256:" + hashlib.sha256(RELATIVE.encode()).hexdigest()
info      = f"{BUILD_ID}:{FILE_ID}:{PATH_HASH}".encode()
salt      = hashlib.sha256(b"MMProtect-HKDF-v1").digest()

build_key = os.urandom(32)
file_key  = HKDF(SHA256(), 32, salt, info, default_backend()).derive(build_key)
plain_php = b'<?php\necho "MMProtect Week2: HTTP lease resolved\\n";\n'
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
    "customerId": "cust_w2", "fileId": FILE_ID,
    "format": "MMENC1", "formatVersion": 1,
    "kdf": "HKDF-SHA256", "keyId": "srv",
    "licenseId": "lic_w2", "manifestHash": "pending",
    "nonce": base64.b64encode(nonce).decode(), "pathHash": PATH_HASH,
    "plainHash": "sha256:" + hashlib.sha256(plain_php).hexdigest(),
    "projectId": "proj_w2", "relativePath": RELATIVE,
    "signature": signature, "tag": base64.b64encode(tag).decode(),
}
hj        = json.dumps(header, separators=(',', ':'), ensure_ascii=True).encode()
container = b"MMENC1\n" + f"{len(hj):08d}".encode() + b"\n" + hj + ciphertext

mmprotect = os.path.join(OUT, ".mmprotect")
os.makedirs(mmprotect, exist_ok=True)

open(f"{OUT}/hello.php",    "wb").write(container)
open(f"{OUT}/expected.txt", "w" ).write("MMProtect Week2: HTTP lease resolved\n")
open(f"{OUT}/build_key_b64.txt", "w").write(base64.b64encode(build_key).decode())

open(f"{mmprotect}/license.json", "w").write(json.dumps({
    "format": "MMENC-LICENSE-1",
    "licenseId": "lic_w2", "projectId": "proj_w2", "customerId": "cust_w2",
    "buildId": BUILD_ID, "licenseServer": "http://127.0.0.1:19876", "features": [],
}))
open(f"{mmprotect}/manifest.json", "w").write(json.dumps({
    "format": "MMENC-MANIFEST-1",
    "projectId": "proj_w2", "customerId": "cust_w2",
    "licenseId": "lic_w2", "buildId": BUILD_ID,
    "version": "1.0.0", "phpMinVersion": "8.1",
    "algorithm": "AES-256-GCM", "kdf": "HKDF-SHA256",
    "files": [], "manifestHash": "pending", "signature": "dev-placeholder",
}))
