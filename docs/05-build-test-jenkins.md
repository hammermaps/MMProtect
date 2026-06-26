# 05 – Build, Tests und Jenkins

## Ziel

Alle drei Projekte sollen reproduzierbar gebaut und getestet werden:

```text
License Server       Windows + Linux
Encoder CLI          Windows + Linux
PHP Decoder Loader   Linux + Windows
```

## One-Click Scripts

Linux:

```text
scripts/linux/build-all.sh
scripts/linux/build-server.sh
scripts/linux/build-encoder.sh
scripts/linux/build-decoder.sh
scripts/linux/test-all.sh
scripts/linux/package-release.sh
scripts/linux/clean.sh
```

Windows:

```text
scripts/windows/build-all.cmd
scripts/windows/build-server.cmd
scripts/windows/build-encoder.cmd
scripts/windows/build-decoder.cmd
scripts/windows/test-all.cmd
scripts/windows/package-release.cmd
scripts/windows/clean.cmd
```

## Erwartete Artefakte

```text
artifacts/
├─ server/
│  ├─ linux-x64/
│  └─ win-x64/
├─ encoder/
│  ├─ linux-x64/
│  └─ win-x64/
├─ decoder/
│  ├─ linux-x64/mmloader.so
│  └─ win-x64/php_mmloader.dll
└─ release/
   └─ mmprotect-<version>.zip
```

## Linux Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y build-essential autoconf pkg-config php8.4-dev php8.4-cli php8.4-opcache libssl-dev libcurl4-openssl-dev
```

Zusätzlich:

```bash
dotnet --info
mysql --version
php -v
phpize --version
```

## Windows Prerequisites

```text
- Visual Studio Build Tools
- PHP 8.4 Devpack passend zur Zielvariante
- PHP SDK für Windows-Builds
- .NET SDK
- MySQL Client optional
```

## Jenkins Linux Pipeline

Siehe:

```text
jenkins/Jenkinsfile.linux
```

Stages:

```text
checkout
restore
build-server
build-encoder
build-decoder
test-server
test-encoder
test-decoder
package
archive
```

## Jenkins Windows Pipeline

Siehe:

```text
jenkins/Jenkinsfile.windows
```

Stages:

```text
checkout
restore
build-server
build-encoder
build-decoder-windows
test-server
test-encoder
test-decoder-windows
package
archive
```

## Gesamt Jenkinsfile

Siehe:

```text
jenkins/Jenkinsfile
```

Diese Pipeline kann Linux- und Windows-Agents parallel verwenden.

## Test-Matrix

```text
Server:
  Unit Tests
  API Integration Tests
  MySQL Integration Tests

Encoder:
  Config JSON
  Config XML
  API Mock
  Encoding
  Manifest

Decoder:
  Plain PHP passthrough
  MMENC1 decode
  Invalid signature
  Invalid license
  Composer autoload
  OPcache enabled
```

## Smoke-Test Ablauf

```text
1. Server starten
2. MySQL Schema importieren
3. Encoder auf tests/php-demo ausführen
4. Decoder mit PHP CLI laden
5. Encoded public/index.php ausführen
6. OPcache-Variante ausführen
```

## Akzeptanzkriterien CI

- Pull Request darf nur grün werden, wenn alle Tests bestehen.
- Artefakte werden versioniert.
- Server und Encoder werden für Windows und Linux veröffentlicht.
- Decoder erzeugt passende `.so` oder `.dll`.
- Testlogs enthalten keine Secrets.
