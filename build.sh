#!/usr/bin/env bash
# Reset the MMProtect application and one explicitly selected SQLite database.
# Application configuration, certificate files, systemd/nginx setup, and SSL
# certificates outside /opt/mmprotect/server are retained by ./update.sh.
# For a non-destructive application update, use ./update.sh instead.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$ROOT/database/sqlite/schema.sql"
DATABASE="${1:-}"

if [[ -z "$DATABASE" || "$DATABASE" != /* ]]; then
    echo "Verwendung: $0 /absoluter/pfad/zur/mmprotect.db" >&2
    echo 'WARNUNG: Dieser Befehl löscht die angegebene SQLite-Datenbank unwiderruflich.' >&2
    exit 2
fi

if [[ ! -f "$SCHEMA" ]]; then
    echo "SQLite-Schema fehlt: $SCHEMA" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo 'sqlite3 ist nicht installiert.' >&2
    exit 1
fi

echo "[build] Dienst anhalten: mmprotect.service"
sudo systemctl stop mmprotect.service

echo "[build] SQLite-Datenbank zurücksetzen: $DATABASE"
sudo rm -f -- "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm"
sudo install -d -o mmprotect -g mmprotect -m 0750 "$(dirname -- "$DATABASE")"
sudo sqlite3 "$DATABASE" < "$SCHEMA"
sudo chown mmprotect:mmprotect "$DATABASE"

echo '[build] Neue Datenbank erstellt; Anwendung aktualisieren'
exec "$ROOT/update.sh"
