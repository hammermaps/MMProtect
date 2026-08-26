#!/usr/bin/env bash
# Build and deploy the MMProtect License Server used by mmprotect.service.
#
# The service must run this exact location:
#   /usr/bin/dotnet /opt/mmprotect/server/MmProtect.LicenseServer.dll \
#       --contentRoot /opt/mmprotect/server
#
# Existing appsettings*.json files are deliberately preserved: they contain the
# production database connection and key-file paths and must never be replaced
# by a repository example configuration.

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

echo '[build] Admin UI bauen'
bash scripts/linux/build-admin-ui.sh

echo '[build] License Server veröffentlichen'
dotnet publish "$PROJECT" -c Release -r linux-x64 --self-contained false -o "$STAGE"

if [[ ! -f "$STAGE/MmProtect.LicenseServer.dll" ]]; then
    echo 'Publish-Ausgabe enthält MmProtect.LicenseServer.dll nicht.' >&2
    exit 1
fi

echo "[deploy] Dienst anhalten: $SERVICE"
sudo systemctl stop "$SERVICE"

echo "[deploy] Serverdateien nach $TARGET synchronisieren"
sudo install -d -m 0755 "$TARGET"
sudo rsync -a --delete-delay --chown=mmprotect:mmprotect \
    --exclude 'appsettings*.json' \
    "$STAGE/" "$TARGET/"

echo "[deploy] Dienst starten: $SERVICE"
sudo systemctl start "$SERVICE"
sudo systemctl is-active --quiet "$SERVICE"

echo '[deploy] Erfolgreich. Status:'
sudo systemctl --no-pager --full status "$SERVICE"
