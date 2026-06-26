#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DECODER="$ROOT/src/PhpDecoderLoader"

if [ ! -d "$DECODER" ]; then
  echo "[build-decoder] Verzeichnis fehlt: $DECODER"
  echo "[build-decoder] Coding-Agent soll native PHP Extension dort anlegen."
  exit 0
fi

cd "$DECODER"

if ! command -v phpize >/dev/null 2>&1; then
  echo "[build-decoder] phpize fehlt. Installiere php8.4-dev/php-dev."
  exit 1
fi

phpize
./configure --enable-mmloader
make -j"$(nproc)"

mkdir -p "$ROOT/artifacts/decoder/linux-x64"
find . -name "mmloader.so" -o -name "*.so" | head -n 1 | while read -r sofile; do
  cp "$sofile" "$ROOT/artifacts/decoder/linux-x64/mmloader.so"
done

echo "[build-decoder] Artefakt: artifacts/decoder/linux-x64/mmloader.so"
