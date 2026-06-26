# 06 – REST API Contract

## Base URL

```text
https://license.example.com
```

## Authentifizierung

### Encoder API

```http
Authorization: Bearer <encoder-api-key>
```

### Runtime API

Runtime Requests enthalten signierte Lizenzdaten und Machine Fingerprint. Optional kann zusätzlich ein Loader-Client-Zertifikat verwendet werden.

## Endpunkte

### GET /health

Response:

```json
{
  "status": "ok",
  "version": "0.1.0",
  "timeUtc": "2026-06-26T12:00:00Z"
}
```

### POST /api/v1/encoder/customers/upsert

Request:

```json
{
  "externalCustomerRef": "demo-kunde",
  "name": "Demo Kunde GmbH",
  "email": "demo@example.invalid",
  "notes": "Demo"
}
```

Response:

```json
{
  "customerId": "cust_01J...",
  "created": true
}
```

### POST /api/v1/encoder/projects/upsert

Request:

```json
{
  "projectKey": "mangelmelder",
  "name": "Mangelmelder",
  "phpMinVersion": "8.4",
  "description": "Projektcode"
}
```

Response:

```json
{
  "projectId": "proj_01J...",
  "created": true
}
```

### POST /api/v1/encoder/licenses/upsert

Request:

```json
{
  "customerId": "cust_01J...",
  "projectId": "proj_01J...",
  "licenseKey": "MM-DEMO-0001",
  "validFrom": "2026-01-01T00:00:00Z",
  "validUntil": "2027-01-01T00:00:00Z",
  "maxActivations": 3,
  "features": ["base"]
}
```

Response:

```json
{
  "licenseId": "lic_01J...",
  "created": true
}
```

### POST /api/v1/encoder/builds/start

Request:

```json
{
  "projectId": "proj_01J...",
  "customerId": "cust_01J...",
  "licenseId": "lic_01J...",
  "version": "1.0.0",
  "sourceRevision": "git-sha",
  "encoderVersion": "0.1.0"
}
```

Response:

```json
{
  "buildId": "build_01J...",
  "keyId": "key_01J...",
  "buildKey": "base64...",
  "manifestSalt": "base64..."
}
```

### POST /api/v1/encoder/builds/{buildId}/files

Request:

```json
{
  "files": [
    {
      "fileId": "file_01J...",
      "relativePath": "src/App/Application.php",
      "pathHash": "sha256:...",
      "plainHash": "sha256:...",
      "cipherHash": "sha256:...",
      "algorithm": "AES-256-GCM",
      "kdf": "HKDF-SHA256"
    }
  ]
}
```

Response:

```json
{
  "accepted": 1,
  "rejected": 0
}
```

### POST /api/v1/encoder/builds/{buildId}/manifest/sign

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
  "vendorPublicKeyId": "vpub_01J...",
  "serverTimeUtc": "2026-06-26T12:00:00Z"
}
```

### POST /api/v1/runtime/lease

Request:

```json
{
  "projectId": "proj_01J...",
  "customerId": "cust_01J...",
  "licenseId": "lic_01J...",
  "buildId": "build_01J...",
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
  "leaseId": "lease_01J...",
  "projectId": "proj_01J...",
  "licenseId": "lic_01J...",
  "buildId": "build_01J...",
  "keyId": "key_01J...",
  "runtimeKey": "base64...",
  "issuedAt": "2026-06-26T12:00:00Z",
  "expiresAt": "2026-06-27T12:00:00Z",
  "graceUntil": "2026-07-03T12:00:00Z",
  "signature": "base64..."
}
```

## Fehlerformat

Alle Fehlerantworten:

```json
{
  "error": {
    "code": "LICENSE_EXPIRED",
    "message": "License is expired.",
    "traceId": "..."
  }
}
```

## Fehlercodes

```text
AUTH_REQUIRED
AUTH_INVALID
VALIDATION_FAILED
CUSTOMER_NOT_FOUND
PROJECT_NOT_FOUND
LICENSE_NOT_FOUND
LICENSE_EXPIRED
LICENSE_REVOKED
ACTIVATION_LIMIT_REACHED
BUILD_NOT_FOUND
MANIFEST_INVALID
LEASE_DENIED
RATE_LIMITED
SERVER_ERROR
```
