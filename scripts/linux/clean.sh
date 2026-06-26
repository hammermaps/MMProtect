#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

rm -rf artifacts
find . -type d -name "bin" -prune -exec rm -rf {} +
find . -type d -name "obj" -prune -exec rm -rf {} +

echo "[clean] Fertig"
