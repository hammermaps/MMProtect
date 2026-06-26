# 00 – Systemübersicht

## Ziel

Es soll ein eigenes System entstehen, um PHP-8.4+-Projektdateien zu verschlüsseln, zu lizenzieren und beim Kunden zur Laufzeit geschützt auszuführen.

Das System besteht aus drei Hauptprojekten:

```text
1. License Server       C# / ASP.NET Core / MySQL
2. Encoder CLI          C# / .NET CLI / JSON+XML-Konfiguration
3. PHP Decoder Loader   native PHP/Zend-Extension für Linux und Windows
```

## Nicht-Ziele

- Kein Malware-/Packersystem.
- Keine Verschlüsselung von Composer selbst.
- Keine Verschlüsselung von `vendor/`, außer später optional für eigene private Composer-Pakete.
- Kein Versprechen absoluter Sicherheit gegen Root/Admin-Zugriff auf Kundensystemen.
- Kein Speichern von Klartext-PHP-Code auf dem Lizenzserver.

## Grundprinzip

```text
Entwicklung
  normaler PHP-Code

Build
  composer install --no-dev --optimize-autoloader --classmap-authoritative
  Encoder CLI verschlüsselt nur Projektdateien
  Encoder registriert Build, Dateien, Kunde und Lizenz beim License Server

Kundensystem
  PHP-FPM/CLI lädt normale .php-Dateien
  PHP Decoder Loader erkennt MMENC1-Dateien
  Loader fordert Runtime-Lease vom License Server an
  Loader entschlüsselt im RAM
  Zend Engine kompiliert
  OPcache cached Opcodes
```

## Ziel-Dateiformat

Jede geschützte `.php`-Datei enthält keinen Klartext-PHP-Code, sondern einen Container:

```text
MMENC1
HeaderLength
CanonicalJsonHeader
Ciphertext
```

Der Header enthält:

```json
{
  "format": "MMENC1",
  "formatVersion": 1,
  "projectId": "project_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "fileId": "file_...",
  "relativePath": "src/App/Application.php",
  "pathHash": "sha256:...",
  "plainHash": "sha256:...",
  "cipherHash": "sha256:...",
  "algorithm": "AES-256-GCM",
  "keyId": "key_...",
  "nonce": "base64...",
  "tag": "base64...",
  "manifestHash": "sha256:...",
  "signature": "base64..."
}
```

## Lizenzserver-Flow beim Encoding

```text
Encoder CLI
  -> authentifiziert sich mit API-Key
  -> erstellt oder findet Kunde
  -> erstellt oder findet Projekt
  -> erstellt Build
  -> fordert Build-Key oder Key-Envelope an
  -> verschlüsselt Dateien lokal
  -> sendet Datei-Metadaten und Hashes
  -> erhält signiertes Manifest
  -> schreibt .mmprotect/manifest.json
```

## Runtime-Flow beim Kunden

```text
PHP require src/App/Application.php
  -> Loader erkennt MMENC1
  -> Loader prüft Header-Signatur
  -> Loader liest Manifest und Lizenzdatei
  -> Loader baut Machine Fingerprint
  -> Loader fordert Runtime Lease per HTTPS REST an
  -> Server prüft Lizenz, Aktivierung, Ablauf, Revocation
  -> Server liefert signierte Lease + Runtime-Key
  -> Loader entschlüsselt Datei im RAM
  -> Zend Engine kompiliert PHP
  -> OPcache speichert Opcodes
```

## OPcache-Sicherheitsproblem

Wenn OPcache bereits Opcodes gespeichert hat, wird die Datei eventuell nicht erneut entschlüsselt. Deshalb muss der Loader zusätzlich prüfen:

```text
Compile-Time Check     beim ersten Entschlüsseln
Request-Time Check     in RINIT regelmäßig oder bei jedem Request
Execute-Time Guard     blockiert geschützte op_arrays bei ungültiger Lizenz
```

## Empfohlene Repo-Struktur

```text
repo/
├─ src/
│  ├─ LicenseServer/
│  ├─ EncoderCli/
│  └─ PhpDecoderLoader/
├─ tests/
│  ├─ php-demo/
│  ├─ server-tests/
│  ├─ encoder-tests/
│  └─ decoder-loader-tests/
├─ database/
│  └─ mysql/
├─ scripts/
│  ├─ linux/
│  └─ windows/
├─ jenkins/
├─ docs/
└─ README.md
```

## Akzeptanzkriterien Gesamtprojekt

- License Server läuft unter Windows und Linux.
- MySQL-Schema wird per SQL oder Migration erzeugt.
- Encoder CLI läuft unter Windows und Linux.
- Encoder kann JSON- und XML-Konfiguration lesen.
- Encoder unterstützt mehrere Projekte in einer Konfiguration.
- Encoder kommuniziert beim Encoding mit dem License Server.
- Encoder erzeugt MMENC1-Dateien mit unveränderter `.php`-Endung.
- Composer bleibt Klartext und kann verschlüsselte Projektklassen laden.
- Decoder Loader kann MMENC1-Dateien laden und normalen Klartext-PHP-Code ignorieren.
- OPcache funktioniert mit verschlüsselten Projektdateien.
- Jenkins baut Linux- und Windows-Artefakte.
- One-Click-Build-Skripte existieren für Windows und Linux.
