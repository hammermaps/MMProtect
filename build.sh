#!/usr/bin/env bash
# Reset the MMProtect application and one explicitly selected SQLite database.
# Application configuration, certificate files, systemd/nginx setup, and SSL
# certificates outside /opt/mmprotect/server are retained by ./update.sh.
# For a non-destructive application update, use ./update.sh instead.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$ROOT/database/sqlite/schema.sql"
CONFIG="${MMPROTECT_CONFIG:-/opt/mmprotect/server/appsettings.Production.json}"

if [[ ! -f "$CONFIG" ]]; then
    echo "Produktionskonfiguration fehlt: $CONFIG" >&2
    exit 1
fi

if [[ ! -f "$SCHEMA" ]]; then
    echo "SQLite-Schema fehlt: $SCHEMA" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo 'sqlite3 ist nicht installiert.' >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo 'python3 wird benötigt, um den SQLite-Pfad aus der Konfiguration zu lesen.' >&2
    exit 1
fi

DATABASE="$(python3 - "$CONFIG" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    config = json.load(file)

if str(config.get("DatabaseProvider", "")).lower() != "sqlite":
    raise SystemExit("build.sh unterstützt nur DatabaseProvider=sqlite.")

connection = str(config.get("ConnectionStrings", {}).get("Sqlite", ""))
match = re.search(r"(?:^|;)\s*data\s+source\s*=\s*([^;]+)", connection, re.IGNORECASE)
if not match:
    raise SystemExit("ConnectionStrings:Sqlite enthält keinen Data Source-Pfad.")

print(match.group(1).strip().strip('\"'))
PY
)"

if [[ "$DATABASE" != /* ]]; then
    echo "SQLite Data Source muss ein absoluter Pfad sein: $DATABASE" >&2
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
