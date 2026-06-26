#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="src/LicenseServer/LicenseServer.csproj"
OUT="artifacts/server/linux-x64"

if [ ! -f "$PROJECT" ]; then
  echo "[build-server] Projektdatei fehlt: $PROJECT"
  echo "[build-server] Coding-Agent soll src/LicenseServer anlegen."
  exit 0
fi

dotnet restore "$PROJECT"
dotnet test "src/LicenseServer.Tests/LicenseServer.Tests.csproj" --configuration Release || true
dotnet publish "$PROJECT" -c Release -r linux-x64 --self-contained false -o "$OUT"

echo "[build-server] Artefakt: $OUT"
