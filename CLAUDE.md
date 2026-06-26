# CLAUDE.md – PHP License Protection System

## Projektübersicht

Dieses Repo enthält ein **vollständiges Spezifikations- und Scaffold-Paket** für ein PHP-Code-Schutzsystem. Alle drei Projekte sind als MVP-Startstand vorhanden (`src/`). License Server und Encoder sind funktional, der PHP Decoder/Loader ist ein Zend-Extension-Skeleton mit noch fehlender Crypto/HTTP-Implementierung. Detaillierten Stand siehe Abschnitt **Implementierungsstand**.

### Die drei Hauptprojekte

| Projekt | Verzeichnis | Sprache | Zweck |
|---|---|---|---|
| License Server | `src/LicenseServer/` | C# / ASP.NET Core | REST API, MySQL, verwaltet Kunden/Lizenzen/Leases |
| Encoder CLI | `src/EncoderCli/` | C# / .NET CLI | Verschlüsselt PHP-Dateien, kommuniziert mit Server |
| PHP Decoder/Loader | `src/PhpDecoderLoader/` | C / C++ (Zend Extension) | Entschlüsselt MMENC1-Dateien in PHP zur Laufzeit |

Alle drei `src/`-Projekte existieren als MVP-Startstand. Vollständiger Stand → Abschnitt **Implementierungsstand**.

---

## Kritische Architekturentscheidungen (nie brechen)

1. **`vendor/` bleibt immer Klartext.** Composer und seine Abhängigkeiten werden nie verschlüsselt.
2. **Verschlüsselte Dateien behalten die Endung `.php`** – damit Composer, Frameworks, `require`, `include` und OPcache normal funktionieren.
3. **Der PHP Decoder/Loader ist in C/C++ implementiert**, nicht in C#. Er muss gegen die Zend/PHP-ABI gebaut werden.
4. **Build-Keys und Runtime-Keys dürfen niemals geloggt werden**, weder im Server noch im Encoder noch im Loader.
5. **Private Signing-Keys kommen nicht ins Git.**
6. **OPcache ist kein Bypass** – der Loader muss Execute-Time-Guards auch für gecachte Opcodes implementieren.

---

## Containerformat MMENC1

Jede geschützte `.php`-Datei hat diesen binären Aufbau:

```
Offset  Größe   Inhalt
0       6       Magic: MMENC1
6       1       LF (\n)
7       8       Header-Länge als ASCII-Dezimal, zero-padded
15      1       LF (\n)
16      N       Canonical JSON Header
16+N    Rest    Binary Ciphertext (AES-256-GCM)
```

Der Header enthält u.a. `projectId`, `customerId`, `licenseId`, `buildId`, `fileId`, `relativePath`, `pathHash`, `plainHash`, `cipherHash`, `algorithm`, `kdf`, `nonce`, `tag`, `manifestHash`, `signature`.

Signaturumfang: magic + header (ohne signature-Feld) + ciphertext-Hash + manifest-Hash + buildId + fileId + pathHash. **Nicht nur den Header signieren** – sonst ist der Ciphertext austauschbar.

---

## Kryptografie

| Zweck | Algorithmus |
|---|---|
| Dateiverschlüsselung | AES-256-GCM |
| Hashing | SHA-256 |
| Key Derivation | HKDF-SHA256 |
| Signaturen | Ed25519 oder RSA-PSS |
| Transport | HTTPS/TLS |

**Schlüsselableitung pro Datei:**
```
fileKey = HKDF(buildKey, buildId + fileId + pathHash)
```

**Canonical JSON** (für stabile Signaturen): UTF-8, sortierte Property-Namen, kein Whitespace, Zeiten UTC ISO-8601, Hashes lowercase hex.

---

## Repo-Struktur

```
repo/
├─ src/                          ← noch zu implementieren
│  ├─ LicenseServer/
│  ├─ EncoderCli/
│  └─ PhpDecoderLoader/
├─ tests/
│  ├─ php-demo/                  ← kleines Demo-PHP-Projekt (Klartext)
│  └─ decoder-loader/            ← Smoke-Tests für die Extension
├─ database/
│  └─ mysql/
│     ├─ schema.sql              ← MySQL-Schema (Grundlage für Server)
│     └─ seed-dev.sql
├─ configs/
│  ├─ encoder.config.json        ← Encoder-Konfigurationsbeispiel
│  ├─ encoder.config.xml
│  ├─ decoder.mmloader.ini       ← PHP-INI für den Loader
│  └─ server.appsettings.example.json
├─ scripts/
│  ├─ linux/                     ← build-all.sh, test-all.sh, ...
│  └─ windows/                   ← build-all.cmd, test-all.cmd, ...
├─ jenkins/
│  ├─ Jenkinsfile
│  ├─ Jenkinsfile.linux
│  └─ Jenkinsfile.windows
├─ tools/templates/              ← JSON-Beispieldateien für Container/Manifest
├─ docs/                         ← Agenten-Spezifikationen (vollständig lesen!)
└─ CLAUDE.md                     ← diese Datei
```

---

## Agenten-Dokumente (Pflichtlektüre vor Implementierung)

Lies **immer zuerst** `docs/00-system-overview.md`, dann nur das für deine Aufgabe relevante Dokument:

| Dokument | Inhalt |
|---|---|
| `docs/00-system-overview.md` | Gesamtarchitektur, Flows, Akzeptanzkriterien |
| `docs/01-agent-license-server.md` | License Server: API, DB-Modell, Sicherheit |
| `docs/02-agent-encoder-cli.md` | Encoder CLI: Befehle, Encoding-Ablauf, Konfiguration |
| `docs/03-agent-php-decoder-loader.md` | Decoder/Loader: Zend-Hooks, OPcache, Build |
| `docs/04-security-crypto-format.md` | Kryptografie, Container-Format, Secrets-Regeln |
| `docs/05-build-test-jenkins.md` | Build-Skripte, Jenkins, Test-Matrix |
| `docs/06-api-contract.md` | REST API: alle Endpunkte, Request/Response, Fehlercodes |

---

## Wo mit der Implementierung beginnen

### Reihenfolge

1. **License Server** – ohne ihn kann der Encoder nicht kommunizieren
2. **Encoder CLI** – benötigt laufenden License Server
3. **PHP Decoder/Loader** – benötigt Encoder-Output und License Server

### License Server (`src/LicenseServer/`)

- ASP.NET Core Minimal API, .NET 8, Dapper + MySqlConnector
- Schema aus `database/mysql/schema.sql`
- Konfiguration in `src/LicenseServer/appsettings.json` (Dev) und `configs/server.appsettings.example.json`
- Alle Endpunkte implementiert – **Krypto ist Demo** (HMAC statt Ed25519, Key-Schutz fehlt)
- Tests mit `dotnet test` (derzeit nur Placeholder)

### Encoder CLI (`src/EncoderCli/`)

- CLI: `mmencoder validate|encode|manifest|clean --config <path> --project <key>`
- Binärname: `mmencoder` (gesetzt in `EncoderCli.csproj`)
- API-Key: `env:MM_ENCODER_API_KEY` oder direkt in Config
- Output: `artifacts/encoded/<projektKey>/` + `.mmprotect/manifest.json` + `.mmprotect/license.json`
- **Vollständig lauffähig**, aber Datei-Signatur ist SHA-256-Hash statt Ed25519

### PHP Decoder/Loader (`src/PhpDecoderLoader/`)

- C, Zend Extension, Linux: `phpize && ./configure --enable-mmloader && make`
- Windows: `config.w32` vorhanden, PHP SDK + Visual Studio Build Tools erforderlich
- MMENC1-Magic-Erkennung funktioniert, **Decryption nicht implementiert**
- Geschützte Dateien werfen `E_COMPILE_ERROR` bis Decoder fertig ist

---

## Runtime-Flow (License Server ↔ Loader)

```
PHP require src/App/Application.php
  → Loader erkennt MMENC1-Magic
  → Header lesen, Signatur prüfen
  → Manifest und license.json lesen
  → Machine Fingerprint berechnen
  → POST /api/v1/runtime/lease senden
  → Server prüft Lizenz, Aktivierungen, Revocation, Ablauf
  → Server antwortet mit signierter Lease + runtimeKey
  → Loader verifiziert Lease-Signatur
  → AES-256-GCM entschlüsseln im RAM
  → PHP-Code an Zend Engine übergeben
  → RAM nullen
  → OPcache speichert Opcodes
```

Der Loader cached die Lease lokal (`mmloader.cache_dir`). Offline-Grace: gecachte Lease gilt bis `graceUntil`. Danach wird geschützter Code blockiert.

---

## Sicherheitsregeln für alle Agenten

**Nie ins Git einchecken:**
- Vendor Signing Private Key
- Encoder API Keys
- Build Keys / Runtime Keys
- MySQL-Passwörter

**Nie in Logs schreiben:**
- `buildKey`, `runtimeKey`, `fileKey`
- Vollständige API-Keys
- Klartext-PHP-Code
- Private Key-Material

**Logs dürfen enthalten:** `licenseId` (gekürzt), `projectId`, `buildId`, `fileCount`, `success/failure`, Fehlercodes

---

## Build & Test

### Linux

```bash
# Prerequisites
sudo apt-get install -y build-essential autoconf pkg-config \
    php8.4-dev php8.4-cli php8.4-opcache libssl-dev libcurl4-openssl-dev dotnet-sdk-8.0

# Alles bauen
scripts/linux/build-all.sh

# Alles testen
scripts/linux/test-all.sh
```

### Windows

```cmd
scripts\windows\build-all.cmd
scripts\windows\test-all.cmd
```

### Artefakte nach Build

```
artifacts/
├─ server/linux-x64/
├─ server/win-x64/
├─ encoder/linux-x64/
├─ encoder/win-x64/
├─ decoder/linux-x64/mmloader.so
├─ decoder/win-x64/php_mmloader.dll
└─ release/mmprotect-<version>.zip
```

### Smoke-Test Ablauf

```bash
# 1. Server starten + Schema importieren
# 2. Encoder auf Demo-Projekt ausführen
mmencoder encode --config configs/encoder.config.json --project mangelmelder
# 3. Decoder-Loader laden und Demo ausführen
php -d zend_extension=./modules/mmloader.so artifacts/encoded/mangelmelder/public/index.php
# 4. Mit OPcache
php -d zend_extension=./modules/mmloader.so -d opcache.enable_cli=1 artifacts/encoded/mangelmelder/public/index.php
```

---

## REST API Kurzreferenz

Basis-URL: `https://license.example.com` (konfigurierbar)

| Methode | Pfad | Auth | Zweck |
|---|---|---|---|
| GET | `/health` | – | Status prüfen |
| POST | `/api/v1/encoder/customers/upsert` | Bearer API-Key | Kunde anlegen/finden |
| POST | `/api/v1/encoder/projects/upsert` | Bearer API-Key | Projekt anlegen/finden |
| POST | `/api/v1/encoder/licenses/upsert` | Bearer API-Key | Lizenz anlegen/finden |
| POST | `/api/v1/encoder/builds/start` | Bearer API-Key | Build starten → buildKey |
| POST | `/api/v1/encoder/builds/{buildId}/files` | Bearer API-Key | Datei-Metadaten registrieren |
| POST | `/api/v1/encoder/builds/{buildId}/manifest/sign` | Bearer API-Key | Manifest signieren |
| POST | `/api/v1/runtime/lease` | Signierte Lizenzdaten | Runtime Lease anfordern |

Fehlerformat: `{ "error": { "code": "...", "message": "...", "traceId": "..." } }`

Fehlercodes: `AUTH_REQUIRED`, `AUTH_INVALID`, `LICENSE_EXPIRED`, `LICENSE_REVOKED`, `ACTIVATION_LIMIT_REACHED`, `LEASE_DENIED`, `RATE_LIMITED`, u.a. – vollständige Liste in `docs/06-api-contract.md`.

---

## Demo-Projekt

`tests/php-demo/` ist ein kleines Composer-kompatibles PHP-Projekt als Encoder-Testbasis.

```bash
cd tests/php-demo
composer dump-autoload -o -a
php public/index.php   # → "MMProtect Demo: protected project code executed"
```

---

## Nicht-Ziele

- Kein absoluter Schutz gegen Root/Admin auf Kundensystemen
- Kein Schutz gegen Debugger auf Prozessspeicher oder modifizierte PHP-Engine
- Keine Verschlüsselung von `vendor/` oder Composer selbst
- Kein Speichern von Klartext-PHP auf dem License Server

---

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

---

## Implementierungsstand (Stand 2026-06-26)

### LicenseServer (`src/LicenseServer/`) — **funktional, Demo-Krypto**

**Dateien:**

| Datei | Inhalt |
|---|---|
| `Program.cs` | Alle 8 REST-Endpunkte als ASP.NET Core Minimal API |
| `Models/Contracts.cs` | Alle Request/Response-Records |
| `Security/ApiKeyValidator.cs` | Bearer-Token-Prüfung gegen `appsettings.json`-Liste |
| `Security/CryptoService.cs` | **DEMO** – HMAC-SHA256 statt Ed25519; Build-Key als `"demo:"+plaintext` gespeichert |
| `Data/MySqlConnectionFactory.cs` | MySqlConnector-Wrapper |
| `Data/DbLookup.cs` | UID→DB-ID-Hilfsfunktionen mit Dapper |
| `appsettings.json` | MySQL-ConnStr, API-Keys, Lease-TTL |
| `LicenseServer.csproj` | .NET 8, Dapper 2.1.66, MySqlConnector 2.4.0 |

**Implementierte Endpunkte:**
- `GET /health` ✓
- `POST /api/v1/encoder/customers/upsert` ✓
- `POST /api/v1/encoder/projects/upsert` ✓
- `POST /api/v1/encoder/licenses/upsert` ✓
- `POST /api/v1/encoder/builds/start` ✓
- `POST /api/v1/encoder/builds/{buildId}/files` ✓
- `POST /api/v1/encoder/builds/{buildId}/manifest/sign` ✓
- `POST /api/v1/runtime/lease` ✓ (inkl. Lizenzstatus, Ablauf, Aktivierungszähler)

**Bekannte Lücken / TODO für Produktion:**

| Problem | Priorität |
|---|---|
| `CryptoService.SignForDemoOnly` nutzt HMAC-SHA256 statt Ed25519/RSA-PSS | KRITISCH |
| `ProtectForDemoOnly` speichert Build-Key als `"demo:"+plaintext` in DB | KRITISCH |
| Keine echte Revocation-Prüfung (`revocations`-Tabelle wird nie abgefragt) | HOCH |
| Kein Audit-Log (Tabelle `audit_log` existiert im Schema, wird nie beschrieben) | HOCH |
| Kein Rate-Limiting für `/runtime/lease` | HOCH |
| `appsettings.json` enthält Dev-API-Key im Klartext | MITTEL |
| `JsonCanonical.Serialize` sortiert Properties nicht (kein echter Canonical-JSON) | MITTEL |
| `Ids.NewId()` erzeugt UUIDs statt ULID-ähnliche IDs (spec: `cust_01J...`) | NIEDRIG |
| Aktivierungszähler-Logik: `activeCount > maxActivations` statt `>=` | NIEDRIG |

**Tests:** `LicenseServer.Tests/SmokeTests.cs` enthält nur einen Placeholder-Test (kein echter Testfall).

---

### EncoderCli (`src/EncoderCli/`) — **vollständig funktional**

**Dateien:**

| Datei | Inhalt |
|---|---|
| `Program.cs` | Dispatcher für `validate`/`encode`/`manifest`/`clean` |
| `CliArgs.cs` | Argument-Parser (`--config`, `--project`, `--verbose`) |
| `Configuration/EncoderConfig.cs` | Vollständiges Config-Modell (JSON + XML, Multi-Projekt) |
| `Configuration/EncoderConfigLoader.cs` | JSON via `System.Text.Json`, XML via `XDocument` |
| `Encoding/CryptoPrimitives.cs` | HKDF-SHA256 (mit festem Salt `MMProtect-HKDF-v1`) + SHA-256-Hashing |
| `Encoding/FileSelector.cs` | Glob-Matching mit `**`-Support, include/exclude |
| `Encoding/MmencContainer.cs` | Echter AES-256-GCM Container, MMENC1-Format |
| `Encoding/ProjectEncoder.cs` | Vollständiger Encoding-Ablauf (Upsert→Build→Encrypt→Sign) |
| `Server/LicenseServerClient.cs` | HTTP-Client gegen License Server mit Bearer-Token |

**Encoding-Ablauf implementiert:** Kunde/Projekt/Lizenz upsert → Build starten → Dateien per Glob selektieren → AES-GCM verschlüsseln → Hashes registrieren → Manifest signieren → `.mmprotect/manifest.json` + `.mmprotect/license.json` schreiben.

**Bekannte Lücken / TODO:**

| Problem | Priorität |
|---|---|
| Datei-Signatur in `MmencContainer` ist SHA-256-Hash statt Ed25519-Signatur | KRITISCH |
| `ManifestHash` in per-Datei-Header bleibt `"pending"` (wird nach Manifest-Erstellung nicht aktualisiert) | HOCH |
| Keine PHP-Syntax-Prüfung vor Verschlüsselung | NIEDRIG |
| Kein HKDF-Salt-Austausch mit Server (Salt ist hartcodiert) | NIEDRIG |

**Tests:** `EncoderCli.Tests/GlobTests.cs` – 3 Theory-Testfälle für Glob-Matching. Keine Crypto- oder Encoding-Tests.

---

### PhpDecoderLoader (`src/PhpDecoderLoader/`) — **Skeleton, nicht lauffähig für geschützte Dateien**

**Dateien:**

| Datei | Inhalt |
|---|---|
| `php_mmloader.h` | Header, Versionskonstante `0.1.0` |
| `config.m4` | Linux phpize-Build-Config, linkt `-lcrypto` |
| `config.w32` | Windows PHP-SDK-Build-Config (Skeleton) |
| `mmloader.c` | Zend Extension mit Compile-Hook und MMENC1-Erkennung |

**Was in `mmloader.c` vorhanden ist:**
- `zend_compile_file`-Hook (MINIT/MSHUTDOWN korrekt verkabelt) ✓
- INI-Parameter vollständig registriert (enabled, license_server, manifest_file, license_file, cache_dir, connect_timeout_ms, request_timeout_ms, lease_refresh_seconds, offline_grace_seconds, require_signature, protected_magic) ✓
- `mmloader_file_starts_with_magic()`: öffnet Datei, liest 6 Bytes, prüft `MMENC1` ✓
- Passthrough für Nicht-MMENC1-Dateien → `original_compile_file()` ✓
- `PHP_MINFO` mit Extension-Info ✓

**Was FEHLT (alle blocking für Produktion):**

| Fehlendes Feature | Datei/Funktion |
|---|---|
| MMENC1-Container parsen (Header-Länge + JSON lesen) | `mmloader_read_plain_demo()` – gibt NULL zurück |
| JSON-Header parsen (cJSON/yyjson) | nicht vorhanden |
| Manifest + license.json lesen | nicht vorhanden |
| Header- und Manifest-Signatur prüfen (OpenSSL Ed25519) | nicht vorhanden |
| Machine Fingerprint berechnen (`/etc/machine-id`, Hostname) | nicht vorhanden |
| HTTPS Runtime-Lease-Request (libcurl) | nicht vorhanden |
| Lease-Signatur verifizieren | nicht vorhanden |
| AES-256-GCM entschlüsseln (OpenSSL EVP) | nicht vorhanden |
| Klartext als `zend_string` an Zend Engine übergeben | Gerüst vorhanden, aber `plain == NULL` |
| RAM nach Entschlüsselung nullen | nicht vorhanden |
| Lease-Cache lokal speichern | nicht vorhanden |
| Offline-Grace-Logik | nicht vorhanden |
| `op_array` als geschützt markieren | TODO-Kommentar in Code |
| `execute_ex`-Hook / OPcache-Guard | nicht vorhanden |
| RINIT Lease-Prüfung | `PHP_RINIT_FUNCTION` registriert, aber leer |

**Aktuelles Verhalten:** Eine MMENC1-Datei führt zu `E_COMPILE_ERROR: "MMENC: protected PHP file detected, but runtime decoder is not implemented yet"`. Klartext-PHP funktioniert normal.

---

### Gesamtübersicht Reifegrad

| Komponente | Reifegrad | Nächster Schritt |
|---|---|---|
| License Server | MVP funktional (Demo-Krypto) | Ed25519 ersetzen, Audit-Log, Revocation |
| Encoder CLI | MVP vollständig lauffähig | Signatur auf Ed25519 umstellen |
| PHP Decoder/Loader | Skeleton (Magic-Detection only) | MMENC1-Parser + libcurl + OpenSSL AES-GCM |
| LicenseServer.Tests | Placeholder | Echte API-Integrationstests |
| EncoderCli.Tests | Nur Glob-Tests | Crypto-Roundtrip, Mock-Server-Tests |
