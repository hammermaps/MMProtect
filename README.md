**MMProtect – PHP License Protection System**  
[![CI](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/dotnet.yml/badge.svg)](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/dotnet.yml)
[![Windows Build](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/windows.yml/badge.svg)](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/windows.yml)
[![CodeQL](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/codeql.yml/badge.svg)](https://github.com/hammermaps/php-license-protection-agent-pack/actions/workflows/codeql.yml)

Ein vollständiges Schutzsystem für PHP-8.4/8.5-Projektcode: verschlüsseln, lizenzieren, zur Laufzeit entschlüsseln.

**Komponenten**

| Komponente | Technologie | Status |
|---|---|---|
| **License Server** | C# / ASP.NET Core 8, MySQL / SQLite | Produktionsbereit |
| **Encoder CLI** | C# / .NET 8 | Vollständig lauffähig |
| **PHP Decoder/Loader** | C (Zend Extension), PHP 8.4 + 8.5 | Vollständig implementiert |

**Tests**

| Suite | Ergebnis |
|---|---|
| LicenseServer.Tests (SmokeTests + CryptoTests) | 41 / 41 ✓ |
| EncoderCli.Tests (Glob + MmIgnore + Compression) | 57 / 57 ✓ |
| E2E-Integrationstest | 7 / 7 ✓ |
| Demo-Projekt-Tests | 31 / 31 ✓ |

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANklEQVR4nO3OQQmAABRAsSfYxZo/jkUsYQLPJrCCNxG2BFtmZquOAAD4i3Ot7mr/egIAwGvXA4rDBc72meO5AAAAAElFTkSuQmCC)

**Wie es funktioniert**

```
┌──────────────┐   AES-256-GCM + ECDSA-P256   ┌──────────────────┐
│ PHP-Quellcode│ ────── Encoder ──────────────►│  .php (MMENC1)   │
└──────────────┘                               └──────────────────┘
                                                        │
                                              PHP lädt .php
                                                        │
                                               ┌────────▼────────┐
                                               │   mmloader.so   │
                                               │  (Zend Hook)    │
                                               └────────┬────────┘
                                                        │ POST /api/v1/runtime/lease
                                               ┌────────▼────────┐
                                               │  License Server  │
                                               │  prüft Lizenz,  │
                                               │  gibt runtimeKey│
                                               └────────┬────────┘
                                                        │ AES-256-GCM entschlüsseln
                                               ┌────────▼────────┐
                                               │  Zend Engine    │
                                               │  (führt aus)    │
                                               └─────────────────┘
```

**Schlüsseleigenschaften:**
- `vendor/` bleibt immer Klartext — Composer funktioniert unverändert
- Verschlüsselte Dateien behalten die `.php`-Endung — `require`/`include`/OPcache laufen normal
- Pro-Datei-Keys via HKDF-SHA256 — ein Schlüssel verrät keinen anderen
- ECDSA-P256-Signaturen auf Datei-, Manifest- und Lease-Ebene
- AES-256-GCM KEK schützt Build-Keys in der Datenbank
- Revocation auf Build- und Lizenzebene, Aktivierungszähler, Audit-Log
- OPcache-Guard via `execute_ex`-Hook — kein Bypass durch Opcode-Cache
- Offline-Grace-Period — Anwendung läuft weiter wenn License Server kurz nicht erreichbar

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OQQmAABRAsSd49m4v6wg/pwmMYQVvImwJtszMXp0BAPAX91pt1fH1BACA164Hoq8EQMMPmF8AAAAASUVORK5CYII=)

**Schnellstart (Docker)**

```bash
cp .env.example .env && chmod 600 .env
# MMPROTECT_ENCODER_API_KEY_0, MMPROTECT_ADMIN_API_KEY_0, MMPROTECT_KEK setzen
docker compose -f docker-compose.sqlite.yml up -d
curl http://localhost:8080/health
```

→ Vollständige Docker-Anleitung: [docs/docker-deployment.md](docs/docker-deployment.md)

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OQQmAABRAsSd49m4v6wg/pwmMYQVvImwJtszMXp0BAPAX91pt1fH1BACA164Hoq8EQMMPmF8AAAAASUVORK5CYII=)

**Schnellstart (Linux, ohne Docker)**

**1. Voraussetzungen installieren**
```bash
sudo apt-get install -y \
    build-essential autoconf pkg-config \
    php8.4-dev php8.4-cli php8.4-opcache \
    libssl-dev libcurl4-openssl-dev \
    dotnet-sdk-8.0 sqlite3 curl git openssl
```

**2. Alles bauen**
```bash
scripts/linux/build-all.sh
```

**3. Signing-Keys generieren**
```bash
scripts/linux/gen-signing-keys.sh ./keys
# → keys/signing-private.pem  (geheim halten!)
# → keys/signing-public.pem   (an Kunden verteilen)
```

**4. E2E-Integrationstest ausführen**
```bash
bash tests/integration/run-integration-test.sh
# → 7 passed, 0 failed
```

**5. .NET-Tests**
```bash
dotnet test src/LicenseServer.Tests/   # 41 Tests
dotnet test src/EncoderCli.Tests/      # 57 Tests
```

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AUBBAsSNhwgJGkPcrHpnRgQU2QtIq6DIze3UGAMBf3Gu1VcfXEwAAXrseaJkELjbMzy0AAAAASUVORK5CYII=)

**Verzeichnisstruktur**
```
src/
├─ LicenseServer/        REST API (MySQL/SQLite, Dapper)
├─ LicenseServer.Tests/  In-Process-Integrationstests via WebApplicationFactory
├─ EncoderCli/           Encoder CLI: mmencoder encode|validate|manifest|clean
├─ EncoderCli.Tests/     Glob- und FileSelector-Tests
└─ PhpDecoderLoader/     Zend Extension in C (mmloader.so / php_mmloader.dll)

database/
├─ mysql/schema.sql      MySQL-Schema (Produktion)
└─ sqlite/schema.sql     SQLite-Schema (Entwicklung / Tests)

tests/
├─ php-demo/             Demo-PHP-Projekt als Encoder-Testbasis
├─ decoder-loader/       Decoder-Tests
└─ integration/          Vollständiger E2E-Test

docs/
├─ operator-guide.md       Installation und Betrieb des License Servers
├─ docker-deployment.md    Docker-Deployment mit Umgebungsvariablen-Referenz
├─ encryption-format.md    MMENC1-Containerformat, HKDF, AES-GCM, ECDSA
├─ build-guide.md          Alle Komponenten bauen und testen
└─ end-user-install.md     mmloader.so auf Kundenserver installieren

scripts/linux/
├─ build-all.sh
├─ test-all.sh
├─ gen-signing-keys.sh
└─ build-decoder-php85.sh
```

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAM0lEQVR4nO3OMQ0AIAwAwdIgBKl1gjacsGCAiZDcTT9+q6oRETMAAPjF6ify6QYAADdyA9Y0AypN+bdfAAAAAElFTkSuQmCC)

**Encoder verwenden**
```bash
# Demo-Projekt vorbereiten
cd tests/php-demo && composer dump-autoload -o -a && cd ../..

# Encoder konfigurieren (Signing-Key eintragen)
cp configs/encoder.config.json my-encoder.config.json
# → signingPrivateKeyFile auf signing-private.pem setzen
# → licenseServer.baseUrl auf License-Server-URL setzen

# Verschlüsseln
mmencoder encode --config my-encoder.config.json --project demo

# Ergebnis prüfen
file artifacts/encoded/demo/src/App/Application.php
# → data (MMENC1-Binary, keine lesbaren PHP-Quellen)
```

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OQQmAABRAsSd49m4v6wg/pwmMYQVvImwJtszMXp0BAPAX91pt1fH1BACA164Hoq8EQMMPmF8AAAAASUVORK5CYII=)

**PHP Decoder/Loader verwenden**
```bash
# Extension laden und verschlüsselte Datei ausführen (Dev-Mode, ohne Server)
php8.4 \
  -d extension=artifacts/decoder/linux-x64/mmloader.so \
  -d mmloader.dev_mode=1 \
  -d mmloader.dev_buildkey_file=artifacts/encoded/demo/.mmprotect/dev-buildkey.b64 \
  artifacts/encoded/demo/public/index.php

# Mit laufendem License Server (Produktion)
php8.4 \
  -d extension=artifacts/decoder/linux-x64/mmloader.so \
  -d mmloader.signing_public_key_file=./keys/signing-public.pem \
  -d mmloader.cache_dir=/var/cache/mmloader \
  artifacts/encoded/demo/public/index.php
```

Vollständige Installationsanleitung: [docs/end-user-install.md](docs/end-user-install.md)

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSNBCkJfFEIwwIgHRiywEZJWQZeZ2ao9AAD+4lyruzq+ngAA8Nr1AOHsBegrsOrIAAAAAElFTkSuQmCC)

**License Server betreiben**

Der Server unterstützt zwei Datenbank-Backends:

| Backend | Verwendung | Konfiguration |
|---|---|---|
| **SQLite** | Entwicklung, Tests, kleines Deployment | `"DatabaseProvider": "sqlite"` |
| **MySQL 8+** | Produktion | `"DatabaseProvider": "mysql"` |

```bash
# Docker (empfohlen)
docker compose -f docker-compose.sqlite.yml up -d

# SQLite (Entwicklung, ohne Docker)
sqlite3 mm_license_dev.db < database/sqlite/schema.sql
dotnet artifacts/server/linux-x64/MmProtect.LicenseServer.dll \
    --contentRoot artifacts/server/linux-x64/
```

Vollständige Betreiber-Dokumentation: [docs/operator-guide.md](docs/operator-guide.md)

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSNBCkJfFEIwwIgHRiywEZJWQZeZ2ao9AAD+4lyruzq+ngAA8Nr1AOHsBegrsOrIAAAAAElFTkSuQmCC)

**Kryptografie**

| Zweck | Algorithmus |
|---|---|
| Dateiverschlüsselung | AES-256-GCM |
| Build-Key-Schutz (DB) | AES-256-GCM (KEK) |
| Key Derivation | HKDF-SHA256 (`fileKey = HKDF(buildKey, buildId:fileId:pathHash)`) |
| Datei- und Lease-Signaturen | ECDSA-P256, DER-Format, SHA-256 |
| Hashes | SHA-256 (lowercase hex) |
| Transport | HTTPS/TLS |

Format-Referenz: [docs/encryption-format.md](docs/encryption-format.md)

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANklEQVR4nO3OQQmAABRAsScYxpg/i2XMYARvRrCCNxG2BFtmZquOAAD4i3Ot7mr/egIAwGvXA22YBcnkstSpAAAAAElFTkSuQmCC)

**Bekannte Einschränkungen**

| Einschränkung | Betrifft | Priorität |
|---|---|---|
| `ManifestHash` im per-Datei-Header bleibt `"pending"` (zweiter Schreibdurchlauf fehlt) | Encoder CLI | HOCH |
| `JsonCanonical.Serialize` sortiert Properties nicht (kein echter Canonical-JSON) | License Server | MITTEL |
| Keine PHP-Syntax-Prüfung vor Verschlüsselung | Encoder CLI | NIEDRIG |

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANklEQVR4nO3OMQ2AABAAsSNBCkJfFEIwwIgHRiywEZJWQZeZ2ao9AAD+4lyruzq+ngAA8Nr1AOHsBegrsOrIAAAAAElFTkSuQmCC)

**Was MMProtect nicht schützt**
- Root/Admin-Zugriff auf dem Kundenserver kann Klartext aus dem RAM lesen
- Ein modifiziertes PHP-Binary kann nach der Entschlüsselung eingreifen
- `vendor/`-Verzeichnis ist und bleibt Klartext

![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANElEQVR4nO3OQQmAABRAsSdYxKa/i8WMIR7ECt5E2BJsmZmt2gMA4C+Otbqr8+sJAACvXQ85PAYartXEogAAAABJRU5ErkJggg==)

**Dokumentation**

**Schnellstart-Anleitungen**

| Anleitung | Zielgruppe | Dauer |
|---|---|---|
| [docs/quickstart-operator.md](docs/quickstart-operator.md) | Serverbetreiber — License Server aufsetzen | ~15 Min. |
| [docs/quickstart-enduser.md](docs/quickstart-enduser.md) | Endkunden — mmloader.so installieren | ~10 Min. |
| [docs/quickstart-developer.md](docs/quickstart-developer.md) | Entwickler — lokaler E2E-Flow | ~20 Min. |

**Vollständige Referenz**

| Dokument | Zielgruppe |
|---|---|
| [docs/operator-guide.md](docs/operator-guide.md) | Serverbetreiber (License Server vollständig) |
| [docs/docker-deployment.md](docs/docker-deployment.md) | Docker-Deployment, Umgebungsvariablen-Referenz |
| [docs/end-user-install.md](docs/end-user-install.md) | Endkunden (Extension vollständig) |
| [docs/build-guide.md](docs/build-guide.md) | Entwickler (Bauen, Testen, CI/CD) |
| [docs/encryption-format.md](docs/encryption-format.md) | Entwickler (Format, Krypto, Protokoll) |
| [docs/06-api-contract.md](docs/06-api-contract.md) | Entwickler (REST API Referenz) |
