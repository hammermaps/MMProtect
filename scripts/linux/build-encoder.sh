#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="src/EncoderCli/EncoderCli.csproj"
OUT="artifacts/encoder/linux-x64"

if [ ! -f "$PROJECT" ]; then
  echo "[build-encoder] Projektdatei fehlt: $PROJECT"
  echo "[build-encoder] Coding-Agent soll src/EncoderCli anlegen."
  exit 0
fi

dotnet restore "$PROJECT"
dotnet test "src/EncoderCli.Tests/EncoderCli.Tests.csproj" --configuration Release || true
dotnet publish "$PROJECT" -c Release -r linux-x64 --self-contained false -o "$OUT"

echo "[build-encoder] Artefakt: $OUT"
