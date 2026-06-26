#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "[build-all] Server bauen"
bash scripts/linux/build-server.sh

echo "[build-all] Encoder bauen"
bash scripts/linux/build-encoder.sh

echo "[build-all] Decoder bauen"
bash scripts/linux/build-decoder.sh

echo "[build-all] Fertig"
