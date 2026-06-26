# PhpDecoderLoader

Native PHP/Zend-Extension für MMENC1-Dateien.

## Linux Build

```bash
cd src/PhpDecoderLoader
phpize
./configure --enable-mmloader
make
```

## Test

```bash
php -d zend_extension=modules/mmloader.so ../../tests/decoder-loader/plain.php
```

## Aktueller Stand

Dies ist ein echter Extension-Startstand mit:

- `config.m4`
- `config.w32`
- INI-Parametern
- `zend_compile_file` Hook
- Erkennung von `MMENC1`
- bewusstem Blockieren geschützter Dateien, solange Decoder/Crypto/HTTP noch nicht implementiert sind

Nächste Implementierungsschritte:

1. MMENC1 Header lesen.
2. Manifest lesen und prüfen.
3. HTTPS Runtime-Lease holen.
4. AES-GCM entschlüsseln.
5. `zend_compile_string` mit Klartext im RAM.
6. OPcache-/execute guard ergänzen.
