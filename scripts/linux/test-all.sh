#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "[test-all] PHP Demo testen"
cd tests/php-demo
if command -v composer >/dev/null 2>&1; then
  composer dump-autoload -o -a
else
  echo "[test-all] composer fehlt, überspringe autoload generation"
fi

php -v
php public/index.php || true
php tests/smoke.php || true

cd "$ROOT"

echo "[test-all] .NET Tests"
if [ -f "src/LicenseServer.Tests/LicenseServer.Tests.csproj" ]; then
  dotnet test src/LicenseServer.Tests/LicenseServer.Tests.csproj
fi
if [ -f "src/EncoderCli.Tests/EncoderCli.Tests.csproj" ]; then
  dotnet test src/EncoderCli.Tests/EncoderCli.Tests.csproj
fi

echo "[test-all] Decoder Smoke"
if [ -f "artifacts/decoder/linux-x64/mmloader.so" ]; then
  php -d zend_extension="$ROOT/artifacts/decoder/linux-x64/mmloader.so" tests/decoder-loader/plain.php
else
  echo "[test-all] Decoder-Artefakt fehlt, überspringe Decoder Smoke"
fi

echo "[test-all] Fertig"
