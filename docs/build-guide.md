# MMProtect Build Guide

This guide covers how to build all three MMProtect components from source on Linux and how to run the test suites. For Windows builds, see `scripts/windows/`.

---

## Prerequisites

### Linux (Ubuntu 22.04 / 24.04)

```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential autoconf pkg-config \
    php8.4-dev php8.4-cli php8.4-opcache \
    libssl-dev libcurl4-openssl-dev \
    dotnet-sdk-8.0 \
    sqlite3 \
    curl git openssl

# Optional: PHP 8.5 loader build
sudo apt-get install -y php8.5-dev php8.5-cli php8.5-opcache

# Optional: Python + cryptography (for test fixtures)
pip3 install cryptography
```

### Verify prerequisites

```bash
dotnet --version           # 8.0.x
php8.4 --version           # PHP 8.4.x
php-config8.4 --version    # 8.4.x
openssl version            # OpenSSL 3.x
```

---

## Build All (one command)

```bash
scripts/linux/build-all.sh
```

This script builds the License Server, Encoder CLI, and PHP Decoder in sequence and places artefacts in `artifacts/`.

---

## Building Individual Components

### License Server

```bash
dotnet publish src/LicenseServer/LicenseServer.csproj \
    -c Release -r linux-x64 --self-contained false \
    -o artifacts/server/linux-x64
```

Output: `artifacts/server/linux-x64/MmProtect.LicenseServer.dll`

### Encoder CLI

```bash
dotnet publish src/EncoderCli/EncoderCli.csproj \
    -c Release -r linux-x64 --self-contained false \
    -o artifacts/encoder/linux-x64
```

Output: `artifacts/encoder/linux-x64/mmencoder`

### PHP Decoder/Loader (PHP 8.4)

```bash
cd src/PhpDecoderLoader
phpize
./configure --enable-mmloader
make -j$(nproc)
mkdir -p ../../artifacts/decoder/linux-x64
cp modules/mmloader.so ../../artifacts/decoder/linux-x64/mmloader.so
```

Or use the helper script:

```bash
scripts/linux/build-decoder.sh
```

Output: `artifacts/decoder/linux-x64/mmloader.so`

### PHP Decoder/Loader (PHP 8.5)

```bash
scripts/linux/build-decoder-php85.sh
```

Output: `artifacts/decoder/linux-x64/mmloader-php85.so`

Requirements: `php8.5-dev` installed (see Prerequisites).

---

## Running Tests

### Unit/Integration tests (.NET)

```bash
dotnet test src/LicenseServer/LicenseServer.Tests/ -v m
dotnet test src/EncoderCli/EncoderCli.Tests/ -v m
```

### Loader smoke tests (Weeks 1–4)

Each week has its own test script in `tests/decoder-loader/`:

```bash
# Week 1: MMENC1 format, basic decrypt
bash tests/decoder-loader/run-tests-week1.sh

# Week 2: HTTP lease against mock server
bash tests/decoder-loader/run-tests-week2.sh

# Week 3: Security gates (expiry, revocation, fingerprint)
bash tests/decoder-loader/run-tests-week3.sh

# Week 4: ECDSA-P256 signing, execute_ex OPcache guard
bash tests/decoder-loader/run-tests-week4.sh
```

### Full end-to-end integration test

```bash
bash tests/integration/run-integration-test.sh
```

This test:
1. Generates ECDSA-P256 signing keys
2. Creates a fresh SQLite database
3. Starts the license server in SQLite mode
4. Runs the encoder on the demo project
5. Executes the encoded PHP with mmloader (dev_mode)
6. Executes with a live HTTP lease from the running server
7. Verifies lease records in SQLite
8. Tests with OPcache enabled
9. Tests with PHP 8.5 (if mmloader-php85.so is present)

Expected output: `7 passed, 0 failed` (PHP 8.5 skipped if not built).

### All tests

```bash
scripts/linux/test-all.sh
```

---

## Generating Signing Keys

```bash
scripts/linux/gen-signing-keys.sh /path/to/output

# Creates:
#   /path/to/output/signing-private.pem  (keep secret)
#   /path/to/output/signing-public.pem   (distribute to customers)
```

**Never commit signing-private.pem to version control.**

---

## Artefact Layout

After a full build:

```
artifacts/
├─ server/
│  ├─ linux-x64/   MmProtect.LicenseServer.dll + appsettings.json
│  └─ win-x64/
├─ encoder/
│  ├─ linux-x64/   mmencoder
│  └─ win-x64/     mmencoder.exe
├─ decoder/
│  ├─ linux-x64/   mmloader.so, mmloader-php85.so
│  └─ win-x64/     php_mmloader.dll
└─ release/
   └─ mmprotect-<version>.zip   (all artefacts zipped)
```

---

## CI/CD (Jenkins)

Jenkinsfiles are provided in `jenkins/`:

- `Jenkinsfile` — multi-platform pipeline
- `Jenkinsfile.linux` — Linux-only build + test
- `Jenkinsfile.windows` — Windows build + test

Key environment variables expected by the pipeline:

| Variable | Description |
|----------|-------------|
| `MM_SIGNING_PRIVATE_KEY` | PEM content of ECDSA private key (Jenkins credential) |
| `MM_ENCODER_API_KEY` | API key for the staging license server |
| `MM_LICENSE_SERVER_URL` | Base URL of the staging license server |

---

## Versioning

The binary name (output) for the encoder is `mmencoder` (set via `<AssemblyName>` in `EncoderCli.csproj`).  
Loader version is set in `src/PhpDecoderLoader/php_mmloader.h` as `PHP_MMLOADER_VERSION`.  
Server version is read from the assembly at runtime (`/health` endpoint).

Update all three in sync before a release.

---

## Troubleshooting Builds

### `phpize` not found

```bash
sudo apt-get install -y php8.4-dev
```

### `libssl-dev` version mismatch

Ensure `libssl-dev` and the `openssl` command point to the same OpenSSL 3.x installation. On Ubuntu 22.04+:

```bash
apt-cache policy libssl-dev openssl
```

### `.NET` SDK version mismatch

Check `global.json` if present. The project targets `net8.0`. Use SDK 8.0.x or later.

### Loader builds but crashes at load time

Check PHP version match: `php --version` must match the PHP headers used during `phpize`. A mismatch causes an ABI error. Build with the dev package for the PHP version your production server runs.
