# 04 – Security- und Crypto-Spezifikation

## Ziel

Diese Spezifikation definiert die Kryptografie, Containerformate und Sicherheitsgrenzen.

## Sicherheitsgrenze

Das System schützt gegen:

```text
- direktes Lesen von PHP-Projektcode
- einfaches Kopieren auf nicht lizenzierte Systeme
- Manipulation geschützter Dateien
- einfache Lizenzumgehung ohne Reverse Engineering
```

Das System schützt nicht vollständig gegen:

```text
- Root/Admin auf Kundensystem
- Debugger auf Prozessspeicher
- modifizierte PHP-Engine
- Reverse Engineering der Loader-Binary
```

## Algorithmen

Empfohlener MVP:

```text
Dateiverschlüsselung: AES-256-GCM
Hashing:              SHA-256
Key Derivation:       HKDF-SHA256
Signaturen:           Ed25519 oder RSA-PSS
Transport:            HTTPS/TLS
```

## Schlüsselarten

```text
Vendor Signing Key
  signiert Manifeste und Runtime-Leases
  Private Key bleibt beim Hersteller/Server

Build Key
  symmetrischer Schlüssel pro Build
  wird beim Encoding verwendet
  wird dem Loader nur als Runtime-Key/Lease bereitgestellt

File Key
  abgeleitet pro Datei
  fileKey = HKDF(buildKey, buildId + fileId + pathHash)

Runtime Lease Key
  zeitlich begrenzter Schlüssel/Build-Key für Kundensystem
```

## MMENC1 Container

Physische Datei:

```text
Offset  Size        Beschreibung
0       6           Magic: MMENC1
6       1           LF
7       8           ASCII Header Length, decimal, zero padded
15      1           LF
16      N           Canonical JSON Header
16+N    rest        Binary Ciphertext
```

Beispiel:

```text
MMENC1
00001234
{"format":"MMENC1",...}
<binary>
```

## Header

```json
{
  "format": "MMENC1",
  "formatVersion": 1,
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "fileId": "file_...",
  "relativePath": "src/App/Application.php",
  "pathHash": "sha256:...",
  "plainHash": "sha256:...",
  "cipherHash": "sha256:...",
  "algorithm": "AES-256-GCM",
  "kdf": "HKDF-SHA256",
  "keyId": "key_...",
  "nonce": "base64...",
  "tag": "base64...",
  "manifestHash": "sha256:...",
  "createdAt": "2026-06-26T12:00:00Z",
  "signature": "base64..."
}
```

## Signaturumfang

Signiert werden muss:

```text
magic
header ohne signature
ciphertext hash
manifest hash
build id
file id
relative path hash
```

Nicht nur den Header signieren. Sonst könnte der Ciphertext ausgetauscht werden.

## Manifest

```json
{
  "format": "MMENC-MANIFEST-1",
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "version": "1.0.0",
  "phpMinVersion": "8.4",
  "algorithm": "AES-256-GCM",
  "kdf": "HKDF-SHA256",
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

## Runtime Lease

```json
{
  "format": "MMENC-LEASE-1",
  "leaseId": "lease_...",
  "projectId": "proj_...",
  "customerId": "cust_...",
  "licenseId": "lic_...",
  "buildId": "build_...",
  "keyId": "key_...",
  "runtimeKey": "base64...",
  "issuedAt": "2026-06-26T12:00:00Z",
  "expiresAt": "2026-06-27T12:00:00Z",
  "graceUntil": "2026-07-03T12:00:00Z",
  "machineFingerprint": "sha256:...",
  "nonce": "base64...",
  "signature": "base64..."
}
```

## Canonical JSON

Damit Signaturen stabil sind, muss JSON canonicalisiert werden:

```text
- UTF-8
- sortierte Property-Namen
- keine unnötigen Whitespaces
- Zeiten in UTC ISO-8601
- Hashes lowercase hex
```

## Geheimnisse

Nie in Git:

```text
Vendor Signing Private Key
Encoder API Keys
Build Keys
Runtime Keys
MySQL Passwörter
```

## Logs

Logs dürfen enthalten:

```text
licenseId gekürzt
projectId
buildId
fileCount
success/failure
error code
```

Logs dürfen nicht enthalten:

```text
buildKey
runtimeKey
fileKey
private key
vollständiger API-Key
Klartext-PHP
```

## Empfohlene Schutzmaßnahmen

```text
- Loader binary strippen
- symbol names reduzieren
- HTTPS certificate pinning optional
- rate limiting serverseitig
- revocation list
- short leases
- OPcache file_cache deaktivieren
- keine Klartext-Fallbacks
```
