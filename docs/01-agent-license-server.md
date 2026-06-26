# 01 – Coding-Agent-Anweisung: License Server

## Rolle des Agenten

Du implementierst den **License Server** für das PHP License Protection System.

Der Server ist eine C# REST API für Windows und Linux mit MySQL-Datenbank. Er verwaltet Kunden, Projekte, Builds, Dateien, Lizenzen, Aktivierungen, Runtime-Leases, Revocations und Audit-Logs.

## Technologie

```text
Sprache:        C#
Runtime:        .NET, plattformübergreifend Windows/Linux
Web:            ASP.NET Core Minimal API oder Controller API
Datenbank:      MySQL / MariaDB
DB-Zugriff:     Dapper oder EF Core
Auth:           API-Key für Encoder, signierte Runtime Requests für Loader
Transport:      HTTPS REST API
Serialisierung: JSON
```

## Projektname

```text
src/LicenseServer
```

## Hauptaufgaben

1. REST API bereitstellen.
2. MySQL-Schema verwenden.
3. Encoder-Authentifizierung per API-Key.
4. Kunden anlegen oder aktualisieren.
5. Projekte anlegen oder aktualisieren.
6. Builds registrieren.
7. Datei-Hashes registrieren.
8. Manifest signieren.
9. Lizenzen erzeugen und verwalten.
10. Runtime-Leases für den PHP Loader ausstellen.
11. Aktivierungen und Machine Fingerprints verwalten.
12. Revocation prüfen.
13. Audit-Log schreiben.

## Datenmodell

Nutze `database/mysql/schema.sql` als Grundlage.

Wichtige Tabellen:

```text
customers
projects
licenses
license_activations
builds
build_files
runtime_leases
api_clients
crypto_keys
revocations
audit_log
```

## API-Endpunkte

Siehe zusätzlich `docs/06-api-contract.md`.

### Health

```http
GET /health
```

Antwort:

```json
{
  "status": "ok",
  "version": "0.1.0"
}
```

### Encoder: Kunde anlegen/finden

```http
POST /api/v1/encoder/customers/upsert
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "externalCustomerRef": "kunde-meier-gmbh",
  "name": "Meier GmbH",
  "email": "it@meier.example",
  "notes": "Pilotkunde"
}
```

Response:

```json
{
  "customerId": "cust_...",
  "created": true
}
```

### Encoder: Projekt anlegen/finden

```http
POST /api/v1/encoder/projects/upsert
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "projectKey": "mangelmelder",
  "name": "Mangelmelder",
  "phpMinVersion": "8.4",
  "description": "Mängelmelder Projektcode"
}
```

### Encoder: Lizenz erzeugen

```http
POST /api/v1/encoder/licenses/upsert
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "customerId": "cust_...",
  "projectId": "proj_...",
  "licenseKey": "MM-2026-0001",
  "validFrom": "2026-01-01T00:00:00Z",
  "validUntil": "2027-01-01T00:00:00Z",
  "maxActivations": 3,
  "features": ["base", "llm_assistant"]
}
```

### Encoder: Build starten

```http
POST /api/v1/encoder/builds/start
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "version": "1.0.0",
  "sourceRevision": "git-sha",
  "encoderVersion": "0.1.0"
}
```

Response:

```json
{
  "buildId": "build_...",
  "keyId": "key_...",
  "buildKey": "base64...",
  "manifestSalt": "base64..."
}
```

Für Produktion soll `buildKey` nicht geloggt werden und nur an authentifizierte interne Encoder ausgegeben werden.

### Encoder: Datei-Metadaten registrieren

```http
POST /api/v1/encoder/builds/{buildId}/files
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "files": [
    {
      "fileId": "file_...",
      "relativePath": "src/App/Application.php",
      "pathHash": "sha256:...",
      "plainHash": "sha256:...",
      "cipherHash": "sha256:...",
      "algorithm": "AES-256-GCM",
      "keyDerivation": "HKDF-SHA256"
    }
  ]
}
```

### Encoder: Manifest signieren

```http
POST /api/v1/encoder/builds/{buildId}/manifest/sign
Authorization: Bearer <encoder-api-key>
```

Request:

```json
{
  "manifestHash": "sha256:...",
  "fileCount": 42
}
```

Response:

```json
{
  "manifestSignature": "base64...",
  "vendorPublicKeyId": "vpub_...",
  "serverTime": "2026-06-26T12:00:00Z"
}
```

### Runtime: Lease anfordern

```http
POST /api/v1/runtime/lease
```

Request:

```json
{
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "manifestHash": "sha256:...",
  "machineFingerprint": "sha256:...",
  "loaderVersion": "0.1.0",
  "phpVersion": "8.4.0",
  "sapi": "fpm-fcgi",
  "nonce": "base64..."
}
```

Response:

```json
{
  "leaseId": "lease_...",
  "projectId": "proj_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "keyId": "key_...",
  "runtimeKey": "base64...",
  "issuedAt": "2026-06-26T12:00:00Z",
  "expiresAt": "2026-06-27T12:00:00Z",
  "graceUntil": "2026-07-03T12:00:00Z",
  "signature": "base64..."
}
```

## Sicherheitsanforderungen

- Alle Encoder-Endpunkte benötigen API-Key.
- API-Keys nur gehasht in DB speichern.
- Runtime-Lease-Antworten müssen signiert werden.
- Runtime-Key niemals in Logs schreiben.
- Build-Key niemals in Logs schreiben.
- Private Signierschlüssel nicht im Git speichern.
- Audit-Log für:
  - Kundenanlage
  - Lizenzanlage
  - Build-Start
  - Manifest-Signatur
  - Lease-Ausgabe
  - Aktivierungsänderung
  - Revocation
- Rate-Limit für Runtime-Lease-Endpunkt.
- Optional IP-Allowlist für Encoder-Endpunkte.

## MySQL-Anforderungen

- `utf8mb4`
- InnoDB
- UTC-Zeitstempel
- Fremdschlüssel
- eindeutige Keys für externe Referenzen
- sinnvolle Indizes für Runtime-Lease-Prüfungen

## Konfiguration

Beispiel: `configs/server.appsettings.example.json`

Der Server muss mindestens konfigurieren können:

```json
{
  "ConnectionStrings": {
    "MySql": "Server=localhost;Database=mm_license;User=mm;Password=secret;"
  },
  "Security": {
    "Issuer": "MM License Server",
    "LeaseTtlMinutes": 1440,
    "GracePeriodDays": 7,
    "RuntimeRateLimitPerMinute": 60
  },
  "Keys": {
    "VendorSigningPrivateKeyPath": "/etc/mmprotect/vendor_signing_private.pem",
    "VendorSigningPublicKeyPath": "/etc/mmprotect/vendor_signing_public.pem"
  }
}
```

## Tests

Implementiere Tests für:

```text
GET /health
Kunde upsert
Projekt upsert
Lizenz upsert
Build starten
Dateien registrieren
Manifest signieren
Runtime-Lease gültig
Runtime-Lease abgelaufene Lizenz
Runtime-Lease zu viele Aktivierungen
Runtime-Lease revokte Lizenz
API-Key fehlt
API-Key falsch
```

## Akzeptanzkriterien

- `dotnet test` läuft erfolgreich.
- Server startet mit MySQL.
- Schema kann initial importiert werden.
- Encoder kann per API einen vollständigen Build registrieren.
- Runtime-Lease liefert signierte Antwort.
- Ungültige Lizenz wird sauber abgelehnt.
- Keine Secrets erscheinen im Log.
- Linux- und Windows-Publish-Artefakte werden erzeugt.
