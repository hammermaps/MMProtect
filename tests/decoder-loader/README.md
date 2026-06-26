# Decoder Loader Tests

Hier liegen einfache Smoke-Test-Dateien für die PHP/Zend-Extension.

Geplante Tests:

```bash
php -d zend_extension=./modules/mmloader.so tests/decoder-loader/plain.php
php -d zend_extension=./modules/mmloader.so -d opcache.enable_cli=1 artifacts/encoded/mangelmelder/public/index.php
```
