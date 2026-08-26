#!/usr/bin/env bash
# Bring an existing MMProtect SQLite database forward without discarding data.
# Run as the account that owns the database (normally via sudo on the server).

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$ROOT/database/sqlite/schema.sql"
DATABASE="${1:?Verwendung: $0 /pfad/zur/mmprotect.db}"

if [[ ! -f "$DATABASE" ]]; then
    echo "SQLite-Datenbank nicht gefunden: $DATABASE" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo 'sqlite3 ist nicht installiert.' >&2
    exit 1
fi

BACKUP="${DATABASE}.before-mmprotect-schema-$(date -u +%Y%m%dT%H%M%SZ).bak"
cp --preserve=mode,timestamps "$DATABASE" "$BACKUP"
echo "Backup erstellt: $BACKUP"

# Create every table/index that did not exist in old installations. Existing
# tables remain untouched; SQLite's CREATE TABLE IF NOT EXISTS never migrates
# their columns, therefore the compatibility columns are handled below.
sqlite3 "$DATABASE" < "$SCHEMA"

has_column() {
    local table="$1"
    local column="$2"
    sqlite3 "$DATABASE" "SELECT 1 FROM pragma_table_info('$table') WHERE name = '$column';" \
        | grep -qx '1'
}

if ! has_column builds manifest_json; then
    sqlite3 "$DATABASE" 'ALTER TABLE builds ADD COLUMN manifest_json TEXT;'
    echo 'Hinzugefügt: builds.manifest_json'
fi

if ! has_column builds download_url; then
    sqlite3 "$DATABASE" 'ALTER TABLE builds ADD COLUMN download_url TEXT;'
    echo 'Hinzugefügt: builds.download_url'
fi

for table in error_reports telemetry_events; do
    if [[ "$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';")" != '1' ]]; then
        echo "Migration unvollständig: Tabelle $table fehlt weiterhin." >&2
        exit 1
    fi
done

echo 'SQLite-Schema erfolgreich aktualisiert.'
