# PHP Demo-Projekt

Dieses Projekt dient als Testdatenbasis für den Encoder und den PHP Decoder Loader.

## Lokal testen

```bash
composer dump-autoload -o -a
php public/index.php
php tests/smoke.php
```

Erwartete Ausgabe:

```text
MMProtect Demo: protected project code executed
Smoke test ok
```

## Encoding-Test

```bash
mmencoder encode --config ../../configs/encoder.config.json --project mangelmelder
```

Danach sollte unter `artifacts/encoded/mangelmelder` ein deploybares Projekt liegen.
