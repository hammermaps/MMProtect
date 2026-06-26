#!/usr/bin/env bash
# Generate an ECDSA-P256 key pair for MMProtect signing.
#
# Usage:
#   scripts/linux/gen-signing-keys.sh [output-dir]
#
# Output:
#   <dir>/signing-private.pem  — private key (keep secret, never commit)
#   <dir>/signing-public.pem   — public key  (embed in loader config)
#
# Loader config (mmloader.ini):
#   mmloader.signing_public_key_file = /path/to/signing-public.pem
#
# Encoder config (encoder.config.json, defaults.signing.privateKeyFile):
#   "signing": { "privateKeyFile": "/path/to/signing-private.pem" }
#
# License Server config (appsettings.json, Security.SigningPrivateKeyFile):
#   "Security": { "SigningPrivateKeyFile": "/path/to/signing-private.pem" }

set -euo pipefail

OUT="${1:-$(pwd)}"
PRIV="$OUT/signing-private.pem"
PUB="$OUT/signing-public.pem"

if [[ ! -d "$OUT" ]]; then
    echo "ERROR: output directory does not exist: $OUT"
    exit 1
fi

if [[ -f "$PRIV" ]]; then
    echo "WARNING: $PRIV already exists — overwriting."
fi

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$PRIV" 2>/dev/null
openssl pkey   -in "$PRIV" -pubout -out "$PUB"
chmod 600 "$PRIV"

echo "Keys generated in $OUT/"
echo "  Private (secret): $PRIV"
echo "  Public  (deploy): $PUB"
echo
echo "Add to .gitignore:"
echo "  signing-private.pem"
