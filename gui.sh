#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/src/EncoderGui/EncoderGui.csproj"
OUT="$ROOT/artifacts/encoder-gui/linux-x64"
APP="$OUT/mmencoder-gui"

if [[ ! -f "$PROJECT" ]]; then
    echo "[gui] GUI-Projekt fehlt: $PROJECT" >&2
    exit 1
fi

echo "[gui] Baue MMProtect Encoder GUI (linux-x64)…"
dotnet publish "$PROJECT" \
    --configuration Release \
    --runtime linux-x64 \
    --self-contained true \
    --output "$OUT"

if [[ ! -x "$APP" ]]; then
    echo "[gui] GUI-Binary wurde nicht erzeugt: $APP" >&2
    exit 1
fi

echo "[gui] Starte MMProtect Encoder GUI…"
exec "$APP" "$@"
