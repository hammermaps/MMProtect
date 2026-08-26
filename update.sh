#!/usr/bin/env bash
# Rebuild and update the MMProtect License Server without touching its data.
# Existing application configuration, certificate files, and /opt/mmprotect/data
# are preserved. System configuration (systemd/nginx) and Let's Encrypt files
# are outside the deployment target and are never modified by this script.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/src/LicenseServer/LicenseServer.csproj"
SERVICE="mmprotect.service"
TARGET="/opt/mmprotect/server"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mmprotect-server-publish.XXXXXX")"

cleanup() {
    rm -rf -- "$STAGE"
}
trap cleanup EXIT

if [[ ! -f "$PROJECT" ]]; then
    echo "Projektdatei fehlt: $PROJECT" >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo 'rsync wird für die sichere Synchronisation nach /opt benötigt.' >&2
    exit 1
fi

cd "$ROOT"

echo '[update] Admin UI bauen'
bash scripts/linux/build-admin-ui.sh

echo '[update] License Server veröffentlichen'
dotnet publish "$PROJECT" -c Release -r linux-x64 --self-contained false -o "$STAGE"

if [[ ! -f "$STAGE/MmProtect.LicenseServer.dll" ]]; then
    echo 'Publish-Ausgabe enthält MmProtect.LicenseServer.dll nicht.' >&2
    exit 1
fi

echo "[update] Dienst anhalten: $SERVICE"
sudo systemctl stop "$SERVICE"

echo "[update] Serverdateien nach $TARGET synchronisieren"
sudo install -d -m 0755 "$TARGET"
sudo rsync -a --delete-delay --chown=mmprotect:mmprotect \
    --exclude 'appsettings*.json' \
    --exclude '*.pfx' \
    --exclude '*.pem' \
    --exclude '*.key' \
    --exclude '*.crt' \
    --exclude '*.cer' \
    "$STAGE/" "$TARGET/"

echo "[update] Dienst starten: $SERVICE"
sudo systemctl start "$SERVICE"
sudo systemctl is-active --quiet "$SERVICE"

echo '[update] Erfolgreich. Status:'
sudo systemctl --no-pager --full status "$SERVICE"
