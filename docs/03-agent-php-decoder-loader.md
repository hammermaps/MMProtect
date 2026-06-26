# 03 – Coding-Agent-Anweisung: PHP Decoder/Loader

## Rolle des Agenten

Du implementierst den **PHP Decoder/Loader**.

Der Loader ist eine native PHP/Zend-Extension für Linux und Windows. Er erkennt MMENC1-Container in `.php`-Dateien, fordert bei Bedarf eine Lizenz-Lease vom License Server an, entschlüsselt den PHP-Code im RAM und übergibt ihn an die Zend Engine.

## Sehr wichtige Architekturentscheidung

Der Loader soll **nicht in C#** implementiert werden.

Begründung:

```text
PHP-Extensions müssen gegen die PHP/Zend-ABI gebaut werden.
OPcache-Integration erfordert Zugriff auf Zend compile hooks.
Windows braucht passende PHP-Thread-Safety-/Non-Thread-Safety-Builds.
```

Verwende daher:

```text
Sprache:        C oder C++
Build Linux:    phpize + configure + make
Build Windows:  PHP SDK / Visual Studio / PHP Devpack
Crypto:         OpenSSL oder libsodium
HTTP:           libcurl oder WinHTTP/Linux curl-Abstraktion
JSON:           cJSON, yyjson oder eigene kleine Parserlogik
```

## Projektname

```text
src/PhpDecoderLoader
```

## Loader-Typ

Ziel ist eine **Zend Extension** oder eine PHP-Extension mit Zend-Hooks.

Empfohlene Namen:

```text
mmloader.so     Linux
php_mmloader.dll Windows
```

## Mindestanforderungen

- PHP 8.4+
- Linux x64
- Windows x64 NTS
- Windows x64 TS optional
- PHP-FPM
- PHP CLI für Tests
- OPcache kompatibel
- Composer-Autoload kompatibel

## INI-Konfiguration

Beispiel: `configs/decoder.mmloader.ini`

```ini
zend_extension=mmloader.so

mmloader.enabled=1
mmloader.license_server=https://license.example.com/api/v1/runtime/lease
mmloader.manifest_file=.mmprotect/manifest.json
mmloader.license_file=.mmprotect/license.json
mmloader.cache_dir=/var/cache/mmloader
mmloader.connect_timeout_ms=3000
mmloader.request_timeout_ms=5000
mmloader.lease_refresh_seconds=3600
mmloader.offline_grace_seconds=604800
mmloader.require_signature=1
mmloader.protected_magic=MMENC1
mmloader.log_level=warn
```

Windows:

```ini
zend_extension=php_mmloader.dll

mmloader.cache_dir=C:\ProgramData\MMProtect\cache
```

## Compile-Hook

Der Loader muss `zend_compile_file` hooken.

Logik:

```text
if Datei beginnt nicht mit MMENC1:
    original_compile_file()

if Datei beginnt mit MMENC1:
    Container lesen
    Header prüfen
    Signatur prüfen
    Manifest prüfen
    Lease sicherstellen
    Runtime-Key ableiten
    AES-GCM entschlüsseln
    Klartext nur im RAM halten
    PHP-Code kompilieren
    Klartext-Puffer nullen
    op_array zurückgeben
```

Pseudocode:

```c
static zend_compile_file_t original_compile_file;

static zend_op_array *mm_compile_file(zend_file_handle *file_handle, int type)
{
    if (!mmloader_is_enabled()) {
        return original_compile_file(file_handle, type);
    }

    if (!mmloader_is_mmenc1(file_handle)) {
        return original_compile_file(file_handle, type);
    }

    mm_container container;
    if (!mmloader_read_container(file_handle, &container)) {
        zend_error(E_COMPILE_ERROR, "MMENC: invalid protected file");
        return NULL;
    }

    if (!mmloader_verify_container_signature(&container)) {
        zend_error(E_COMPILE_ERROR, "MMENC: invalid signature");
        return NULL;
    }

    if (!mmloader_ensure_runtime_lease(&container)) {
        zend_error(E_COMPILE_ERROR, "MMENC: license invalid or expired");
        return NULL;
    }

    zend_string *plain = mmloader_decrypt(&container);
    if (!plain) {
        zend_error(E_COMPILE_ERROR, "MMENC: decrypt failed");
        return NULL;
    }

    zend_op_array *op_array = zend_compile_string(
        plain,
        ZSTR_VAL(file_handle->filename),
        ZEND_COMPILE_POSITION_AFTER_OPEN_TAG
    );

    mmloader_mark_op_array_protected(op_array, &container);
    mmloader_secure_zero_and_release(plain);

    return op_array;
}
```

## OPcache-Anforderung

OPcache darf nicht zum Lizenz-Bypass werden.

Implementiere zusätzlich:

```text
RINIT:
  Lease prüfen oder Ablaufzeit prüfen

execute_ex hook:
  Für geschützte op_arrays prüfen, ob Lizenz noch gültig ist.
```

Wichtig:

```text
Compile-Time reicht nicht.
OPcache kann bereits kompilierte Opcodes liefern.
Der Loader muss auch gecachte geschützte Opcodes kontrollieren.
```

## Protected op_array Marker

Der Loader muss geschützte op_arrays kennzeichnen.

Optionen:

```text
op_array.reserved[] verwenden, wenn sauber verfügbar
interne HashMap nach op_array pointer
HashMap nach filename + buildId + fileId
```

Für MVP:

```text
HashMap filename -> protected metadata
```

Für Produktion:

```text
robuster op_array marker + lifecycle cleanup
```

## Composer-Verhalten

Composer bleibt Klartext.

Beispiel:

```php
require __DIR__ . '/../vendor/autoload.php';

$app = new App\Application();
$app->run();
```

Composer ruft `require src/App/Application.php` auf. Der Loader greift automatisch, weil die Datei mit `MMENC1` beginnt.

## Lizenzserver-Kommunikation

Der Loader sendet:

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

Der Loader empfängt:

```json
{
  "leaseId": "lease_...",
  "runtimeKey": "base64...",
  "expiresAt": "2026-06-27T12:00:00Z",
  "graceUntil": "2026-07-03T12:00:00Z",
  "signature": "base64..."
}
```

Die Signatur muss geprüft werden.

## Offline Grace

Der Loader darf eine signierte Lease lokal cachen.

Regeln:

```text
Online:
  Lease erneuern

Offline:
  gecachte Lease verwenden, solange graceUntil gültig ist

Grace abgelaufen:
  geschützten Code blockieren
```

Lokaler Cache darf nicht Klartext-Dateien enthalten.

## Machine Fingerprint

Nutze eine weiche Bindung:

Linux:

```text
/etc/machine-id
Hostname
Install-ID aus cache_dir
```

Windows:

```text
MachineGuid
ComputerName
Install-ID aus ProgramData
```

Hash:

```text
sha256(normalized values)
```

Nicht zu viele Hardwaredaten verwenden, damit normale Serveränderungen nicht ständig Aktivierungen brechen.

## Fehlerausgabe

Fatal Errors sollten verständlich, aber nicht geheimnisverratend sein:

```text
MMENC: protected file invalid
MMENC: license invalid or expired
MMENC: license server unavailable and offline grace expired
MMENC: unsupported format version
MMENC: unsupported PHP version
```

Nicht ausgeben:

```text
Keys
Runtime-Key
Build-Key
Private Details der Kryptografie
Server-Stacktraces
```

## Tests

### CLI-Tests

```bash
php -d zend_extension=./modules/mmloader.so tests/decoder-loader/plain.php
php -d zend_extension=./modules/mmloader.so tests/decoder-loader/protected.php
php -d zend_extension=./modules/mmloader.so -d opcache.enable_cli=1 tests/php-demo/public/index.php
```

### Testfälle

```text
Klartext-PHP läuft unverändert
MMENC1-Datei wird entschlüsselt
falsche Signatur wird blockiert
abgelaufene Lizenz wird blockiert
offline grace funktioniert
Composer-Autoload lädt geschützte Klasse
OPcache enabled läuft
OPcache cached Datei läuft nicht nach Lizenzablauf weiter
```

## Build Linux

```bash
phpize
./configure --enable-mmloader
make
make test
```

## Build Windows

Windows braucht einen separaten Build mit PHP SDK, Visual Studio Build Tools und PHP Devpack.

Zielartefakte:

```text
php_mmloader-php84-nts-x64.dll
php_mmloader-php84-ts-x64.dll
```

## Akzeptanzkriterien

- Klartext-PHP bleibt lauffähig.
- Geschützte `.php`-Dateien werden erkannt.
- Ungültige Signatur wird abgelehnt.
- Lizenzserver-Lease wird angefordert.
- Runtime-Key wird nur im RAM gehalten.
- Composer-Autoload funktioniert.
- OPcache funktioniert.
- Execute-Time-Guard verhindert Lizenz-Bypass bei gecachten Opcodes.
- Linux-Build erzeugt `.so`.
- Windows-Build erzeugt `.dll`.
