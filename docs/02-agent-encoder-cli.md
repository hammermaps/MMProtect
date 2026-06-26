# 02 – Coding-Agent-Anweisung: Encoder CLI

## Rolle des Agenten

Du implementierst den **Encoder CLI**.

Der Encoder ist ein C# CLI-Tool für Windows und Linux. Er verschlüsselt PHP-Projektdateien, kommuniziert beim Encodieren mit dem License Server und erzeugt ein deploybares Projektpaket.

Composer und `vendor/` bleiben Klartext. Nur konfigurierbare Projektpfade werden verschlüsselt.

## Technologie

```text
Sprache:        C#
Runtime:        .NET, plattformübergreifend Windows/Linux
CLI Parser:     System.CommandLine oder eigene einfache Parserlogik
Config:         JSON und XML
HTTP:           HTTPS REST API zum License Server
Crypto:         AES-256-GCM, SHA-256, HKDF-SHA256
Output:         geschützte .php-Dateien mit MMENC1-Container
```

## Projektname

```text
src/EncoderCli
```

## CLI-Ziele

Der Encoder muss folgende Befehle unterstützen:

```bash
mmencoder validate --config encoder.config.json
mmencoder encode --config encoder.config.json --project mangelmelder
mmencoder encode --config encoder.config.xml --project mangelmelder
mmencoder manifest --config encoder.config.json --project mangelmelder
mmencoder clean --config encoder.config.json --project mangelmelder
```

## Konfigurationsmodell

Beispiele liegen unter:

```text
configs/encoder.config.json
configs/encoder.config.xml
```

Die Konfiguration muss mehrere Projekte enthalten können.

### JSON-Beispiel

```json
{
  "licenseServer": {
    "baseUrl": "https://license.example.com",
    "apiKey": "env:MM_ENCODER_API_KEY",
    "timeoutSeconds": 30
  },
  "defaults": {
    "phpMinVersion": "8.4",
    "algorithm": "AES-256-GCM",
    "keepPhpExtension": true,
    "writeManifest": true
  },
  "projects": [
    {
      "projectKey": "mangelmelder",
      "name": "Mangelmelder",
      "version": "1.0.0",
      "sourceRoot": "./tests/php-demo",
      "outputRoot": "./artifacts/encoded/mangelmelder",
      "customer": {
        "externalCustomerRef": "demo-kunde",
        "name": "Demo Kunde GmbH",
        "email": "demo@example.invalid"
      },
      "license": {
        "licenseKey": "MM-DEMO-0001",
        "validUntil": "2027-01-01T00:00:00Z",
        "maxActivations": 3,
        "features": ["base"]
      },
      "include": [
        "src/**/*.php",
        "config/**/*.php"
      ],
      "exclude": [
        "vendor/**",
        "public/assets/**",
        "storage/**",
        "cache/**",
        "logs/**",
        ".env",
        "composer.json",
        "composer.lock"
      ],
      "copyPlain": [
        "public/**",
        "vendor/**",
        "composer.json",
        "composer.lock"
      ]
    }
  ]
}
```

## Encoding-Ablauf

```text
1. Konfiguration laden
2. Projekt anhand --project auswählen
3. API-Key aus Config oder Environment laden
4. Verbindung zum License Server testen
5. Kunde upsert
6. Projekt upsert
7. Lizenz upsert
8. Build starten und Build-Key erhalten
9. Ausgabeordner vorbereiten
10. copyPlain-Dateien kopieren
11. include-Dateien sammeln
12. exclude-Regeln anwenden
13. Jede Datei:
    - Klartext lesen
    - PHP-Syntax optional prüfen
    - fileId erzeugen
    - fileKey = HKDF(buildKey, buildId + fileId + pathHash)
    - AES-256-GCM verschlüsseln
    - MMENC1-Container schreiben
    - Hashes sammeln
14. Datei-Metadaten beim Server registrieren
15. Manifest erzeugen
16. Manifest-Hash vom Server signieren lassen
17. .mmprotect/manifest.json schreiben
18. .mmprotect/license.json schreiben
19. Build-Zusammenfassung ausgeben
```

## Containerformat

Die Ausgabe-Datei behält ihre Endung `.php`.

Beispiel:

```text
src/App/Application.php
```

Inhalt:

```text
MMENC1
00001234
{...canonical json header...}
<binary ciphertext>
```

Für die erste MVP-Version ist alternativ Base64 für Ciphertext erlaubt, aber die Zielvariante soll binary-safe sein.

## Manifest

Der Encoder erzeugt:

```text
.mmprotect/manifest.json
```

Beispiel siehe `tools/templates/manifest.example.json`.

Manifest enthält:

```json
{
  "format": "MMENC-MANIFEST-1",
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "version": "1.0.0",
  "phpMinVersion": "8.4",
  "files": [
    {
      "fileId": "file_...",
      "relativePath": "src/App/Application.php",
      "pathHash": "sha256:...",
      "plainHash": "sha256:...",
      "cipherHash": "sha256:..."
    }
  ],
  "manifestHash": "sha256:...",
  "signature": "base64..."
}
```

## Lizenzdatei

Der Encoder erzeugt:

```text
.mmprotect/license.json
```

Sie enthält keine Runtime-Keys und keine privaten Schlüssel.

```json
{
  "format": "MMENC-LICENSE-1",
  "licenseId": "lic_...",
  "licenseKey": "MM-DEMO-0001",
  "customerId": "cust_...",
  "projectId": "proj_...",
  "buildId": "build_...",
  "licenseServer": "https://license.example.com",
  "features": ["base"]
}
```

## Composer-Verhalten

Der Encoder darf `vendor/` nicht verschlüsseln.

Vor dem Encoding soll der Nutzer ausführen:

```bash
composer install --no-dev --optimize-autoloader --classmap-authoritative
```

Für das Testprojekt reicht:

```bash
composer dump-autoload -o -a
```

Danach kopiert der Encoder `vendor/` unverändert in den Output.

## Fehlerbehandlung

Der Encoder muss aussagekräftige Fehler liefern:

```text
CONFIG_NOT_FOUND
PROJECT_NOT_FOUND
SERVER_UNAVAILABLE
API_AUTH_FAILED
CUSTOMER_UPSERT_FAILED
PROJECT_UPSERT_FAILED
LICENSE_UPSERT_FAILED
BUILD_START_FAILED
FILE_READ_FAILED
FILE_ENCRYPT_FAILED
MANIFEST_SIGN_FAILED
OUTPUT_WRITE_FAILED
```

## Logging

- Normale Ausgabe an Console.
- `--verbose` für Details.
- Keine Secrets loggen.
- Keine BuildKeys loggen.
- Keine AES-Keys loggen.
- Keine kompletten API-Keys loggen.

## Tests

Implementiere Tests für:

```text
JSON Config laden
XML Config laden
Projekt auswählen
Include/Exclude Matching
copyPlain-Verhalten
AES-GCM Roundtrip
HKDF deterministic
MMENC1 Header schreiben/lesen
Server API Mock
Manifest Hash stabil
Fehler bei fehlendem API-Key
```

## Akzeptanzkriterien

- `mmencoder validate` funktioniert für JSON und XML.
- `mmencoder encode` erzeugt Output-Projekt.
- `vendor/` bleibt Klartext.
- `src/**/*.php` ist als MMENC1 geschützt.
- `public/index.php` bleibt lauffähiger Klartext-Bootstrap.
- `.mmprotect/manifest.json` wird erzeugt.
- `.mmprotect/license.json` wird erzeugt.
- Server-Datensätze werden beim Encoding erstellt.
- Linux- und Windows-Builds werden erzeugt.
