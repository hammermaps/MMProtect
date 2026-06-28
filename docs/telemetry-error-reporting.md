# MMProtect — Telemetrie & Fehlerberichte

Dieses Dokument beschreibt die beiden optionalen Feedback-Kanäle zwischen dem Kunden-Server (PHP Loader + Encoder) und dem License Server.

Beide Features sind **standardmäßig deaktiviert** und erfordern ein explizites Opt-in. Es werden keine sicherheitsrelevanten Daten übertragen (kein buildKey, kein runtimeKey, kein Quellcode, keine API-Keys).

---

## Übersicht

| Feature | Richtung | Standard | Konfiguration |
|---------|----------|----------|---------------|
| **Fehlerberichte** | Loader → Server | Aus | `mmloader.error_reporting = 1` |
| **Loader-Telemetrie** | Loader → Server | Aus | `mmloader.telemetry = 1` |
| **Encoder-Telemetrie** | Encoder → Server | Aus | `"telemetry": { "enabled": true }` |

---

## Fehlerberichte (Error Reporting)

### Was wird gesendet?

Nach jeder PHP-Request-Verarbeitung sendet der mmloader einen Batch aller aufgezeichneten PHP-Fehler an den License Server — sofern in dieser Request mindestens ein geschütztes PHP-File entschlüsselt wurde. Nicht-geschützte Requests erzeugen keine Berichte.

**Felder pro Fehler:**
- PHP-Fehlerlevel (Integer, z.B. `E_WARNING = 2`)
- Fehlermeldung (Text)
- Dateiname (falls vorhanden)
- Zeilennummer (falls vorhanden)
- Zeitstempel (UTC ISO-8601)

**Zusätzlich im Batch:**
- `licenseId`, `buildId` (zur Zuordnung beim Entwickler)
- `machineFingerprint` (SHA-256-Hash von `/etc/machine-id` + hostname — kein PII)
- PHP-Version, SAPI-Typ

### Was wird NICHT gesendet?
- Quellcode (weder verschlüsselt noch entschlüsselt)
- `buildKey` / `runtimeKey` / `fileKey`
- POST-Daten oder HTTP-Headers der PHP-Request
- Datenbankpasswörter oder Verbindungsstrings aus dem PHP-Kontext

### Konfiguration (php.ini)

```ini
; Aktiviert Fehlerberichte (Standard: 0 = aus)
mmloader.error_reporting = 1

; Endpunkt für Fehler-Batches
; Standard: <mmloader.license_server>/api/v1/runtime/errors
; mmloader.error_report_url = https://other-server.example.com/api/v1/runtime/errors

; Maximale Anzahl Fehler pro Request-Batch (Standard: 20)
mmloader.error_report_max_per_request = 20

; PHP-Fehlerlevel-Bitmask (Standard: 32767 = E_ALL)
; Beispiel — nur Errors und Warnings: 3
; E_ERROR=1, E_WARNING=2, E_PARSE=4, E_NOTICE=8, E_STRICT=2048,
; E_USER_ERROR=256, E_USER_WARNING=512, E_USER_NOTICE=1024,
; E_DEPRECATED=8192, E_USER_DEPRECATED=16384
mmloader.error_report_level = 32767
```

### Serveradmin: Fehlerberichte abfragen

```bash
# Alle Fehler (neueste zuerst, max 100)
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/error-reports"

# Gefiltert nach Lizenz
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/error-reports?licenseId=lic_01J..."

# Gefiltert nach Build
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/error-reports?buildId=build_01J...&limit=50"
```

Antwortformat:

```json
{
  "reports": [
    {
      "id": 1,
      "licenseId": "lic_01J...",
      "buildId": "build_01J...",
      "reportedAt": "2026-06-29T10:05:01Z",
      "errorLevel": 2,
      "errorMessage": "Undefined variable $foo",
      "errorFile": "src/App/Controller.php",
      "errorLine": 42,
      "phpVersion": "8.4.1",
      "sapi": "fpm-fcgi",
      "machineFingerprint": "sha256:abc123..."
    }
  ]
}
```

### Technisches Detail (mmloader)

Der mmloader installiert in `MINIT` einen `zend_error_cb`-Hook. Beim Auftreten eines PHP-Fehlers wird geprüft:
1. Ist `error_reporting_enabled` aktiv?
2. Ist ein aktiver Lease vorhanden (`has_cached_key`)?
3. Passt der Fehlerlevel auf `error_report_level_mask`?
4. Wurde das Per-Request-Limit (`error_report_max`) noch nicht erreicht?

Nur wenn alle vier Bedingungen erfüllt sind, wird der Fehler in ein cJSON-Array eingereicht. In `RSHUTDOWN` wird das Array als JSON an den Server gesendet (fire-and-forget, max. 3 s Timeout). Danach wird der Heap-Speicher freigegeben.

---

## Loader-Telemetrie

### Was wird gesendet?

Der Loader sendet einfache Lease-Lifecycle-Ereignisse nach jeder erfolgreich abgeschlossenen Lease-Operation:

| Event | Wann |
|-------|------|
| `lease_acquired` | HTTP-Lease vom Server erfolgreich geholt |
| `lease_offline_grace` | Disk-Cache verwendet, weil Server nicht erreichbar (Grace Period aktiv) |

**Felder:**
- `source`: `"loader"`
- `eventType`: (s.o.)
- `licenseId`, `buildId`, `projectId`
- `occurredAt` (UTC ISO-8601)
- `data`: `{ "phpVersion": "8.4.1", "sapi": "fpm-fcgi" }`

### Was wird NICHT gesendet?
- `buildKey`, `runtimeKey`, `fileKey`
- Quellcode
- HTTP-Request-Daten des PHP-Clients
- Maschinenfingerabdruck (nur bei Fehlerberichten)

### Konfiguration (php.ini)

```ini
; Aktiviert Loader-Telemetrie (Standard: 0 = aus)
mmloader.telemetry = 1

; Endpunkt für Telemetrie-Events
; Standard: <mmloader.license_server>/api/v1/telemetry/loader
; mmloader.telemetry_url = https://other-server.example.com/api/v1/telemetry/loader
```

---

## Encoder-Telemetrie

### Was wird gesendet?

Der EncoderCLI kann nach jedem Build Lifecycle-Ereignisse an den License Server senden:

| Event | Wann |
|-------|------|
| `build_started` | Direkt nach `builds/start` — Build-ID ist bekannt |
| `build_completed` | Nach erfolgreichem `manifest/sign` |

**Felder im `data`-Objekt (build_completed):**
- `fileCount`: Anzahl verschlüsselter Dateien
- `durationMs`: Gesamtdauer in Millisekunden
- `compressionEnabled`: `"true"` oder `"false"` (LZ4)
- `obfuscateEnabled`: `"true"` oder `"false"`
- `optimizeEnabled`: `"true"` oder `"false"`

### Was wird NICHT gesendet?
- `buildKey`
- Dateinamen oder Quellcode-Fragmente
- API-Keys

### Konfiguration (encoder.config.json)

```json
{
  "licenseServer": { "..." },
  "telemetry": {
    "enabled": false,
    "endpointUrl": ""
  },
  "projects": [...]
}
```

Oder in `encoder.config.xml`:

```xml
<telemetry enabled="false" endpointUrl="" />
```

`endpointUrl` ist optional — fällt auf `<licenseServer.baseUrl>/api/v1/encoder/telemetry` zurück.

### Serveradmin: Telemetrie abfragen

```bash
# Alle Telemetrie-Events (neueste zuerst, max 200)
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/telemetry"

# Nur Encoder-Events
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/telemetry?source=encoder"

# Loader-Events für eine Lizenz
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/telemetry?source=loader&licenseId=lic_01J..."

# Projektbezogen
curl -H "Authorization: Bearer ADMIN_KEY" \
  "https://license.example.com/api/v1/admin/telemetry?projectId=proj_01J...&limit=500"
```

Antwortformat:

```json
{
  "events": [
    {
      "id": 1,
      "source": "encoder",
      "eventType": "build_completed",
      "licenseId": "lic_01J...",
      "buildId": "build_01J...",
      "projectId": "proj_01J...",
      "occurredAt": "2026-06-29T10:00:00Z",
      "payloadJson": "{\"fileCount\":\"42\",\"durationMs\":\"1234\",\"compressionEnabled\":\"true\"}"
    }
  ]
}
```

---

## Datenbankschema

Beide Features schreiben in getrennte Tabellen:

```sql
-- Fehlerberichte (error_reports)
CREATE TABLE error_reports (
  id                  INTEGER PRIMARY KEY,
  build_id            INTEGER REFERENCES builds(id) ON DELETE SET NULL,
  license_uid         TEXT NOT NULL,
  machine_fingerprint TEXT,
  reported_at         TEXT NOT NULL,
  error_level         INTEGER NOT NULL,
  error_message       TEXT NOT NULL,
  error_file          TEXT,
  error_line          INTEGER,
  php_version         TEXT,
  sapi                TEXT
);

-- Telemetrie-Ereignisse (telemetry_events)
CREATE TABLE telemetry_events (
  id           INTEGER PRIMARY KEY,
  source       TEXT NOT NULL,  -- 'encoder' | 'loader'
  event_type   TEXT NOT NULL,
  license_uid  TEXT,
  build_uid    TEXT,
  project_uid  TEXT,
  payload_json TEXT,
  occurred_at  TEXT NOT NULL,
  client_ip    TEXT
);
```

---

## Sicherheitshinweise

- Fehlerberichte und Telemetrie sind **Opt-in** auf der Kundenseite — der Entwickler kann sie nicht erzwingen.
- Beide Kanäle sind **fire-and-forget** — ein Fehler beim Senden bricht weder den PHP-Request ab noch verhindert er weitere Requests.
- Der Serverendpunkt für Loader-Telemetrie (`/api/v1/telemetry/loader`) erfordert **kein Secret** — nur `licenseId`. Da die Daten nicht sicherheitsrelevant sind, ist das akzeptabel. Rate-Limiting (IP-basiert) schützt vor Missbrauch.
- Fehlerberichte werden **gelöscht-gebaut** wenn der zugehörige Build gelöscht wird (`ON DELETE SET NULL` auf `build_id`).
- Datenaufbewahrung: Es gibt kein automatisches Pruning — legen Sie ggf. einen Cron-Job an, der alte Einträge bereinigt:

```sql
-- Fehlerberichte älter als 90 Tage löschen
DELETE FROM error_reports WHERE reported_at < datetime('now', '-90 days');

-- Telemetrie älter als 180 Tage löschen
DELETE FROM telemetry_events WHERE occurred_at < datetime('now', '-180 days');
```
