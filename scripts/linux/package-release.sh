#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"
mkdir -p artifacts/release

ZIP="artifacts/release/mmprotect-${VERSION}.zip"
rm -f "$ZIP"

if command -v zip >/dev/null 2>&1; then
  zip -r "$ZIP" artifacts/server artifacts/encoder artifacts/decoder configs docs database scripts jenkins
  echo "[package-release] $ZIP"
else
  tar -czf "artifacts/release/mmprotect-${VERSION}.tar.gz" artifacts/server artifacts/encoder artifacts/decoder configs docs database scripts jenkins
  echo "[package-release] artifacts/release/mmprotect-${VERSION}.tar.gz"
fi
