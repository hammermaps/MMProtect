#!/usr/bin/env bash
# Build mmloader.so for PHP 8.5.
# Requires php8.5-dev: sudo apt-get install -y php8.5-dev
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DECODER="$ROOT/src/PhpDecoderLoader"
ARTIFACT="$ROOT/artifacts/decoder/linux-x64/mmloader-php85.so"

if [ ! -d "$DECODER" ]; then
    echo "ERROR: $DECODER not found" >&2
    exit 1
fi

if ! command -v phpize8.5 &>/dev/null && ! command -v php8.5 &>/dev/null; then
    echo "ERROR: php8.5-dev not installed." >&2
    echo "  sudo apt-get install -y php8.5-dev" >&2
    exit 1
fi

PHPIZE85="$(command -v phpize8.5 2>/dev/null || echo phpize)"
PHPCONFIG85="$(command -v php-config8.5 2>/dev/null || echo php-config)"

# Build in a clean temp copy to avoid contaminating the PHP 8.4 build artifacts.
BUILD_DIR="$(mktemp -d /tmp/mmloader-php85-build-XXXXXX)"
cp -r "$DECODER/." "$BUILD_DIR/"
cd "$BUILD_DIR"

# Clean any leftover 8.4 build artifacts before phpize.
"$PHPIZE85" --clean 2>/dev/null || true
"$PHPIZE85"
./configure --enable-mmloader --with-php-config="$PHPCONFIG85"
make -j"$(nproc)"

mkdir -p "$(dirname "$ARTIFACT")"
find . -name "mmloader.so" -o -name "*.so" | head -n 1 | while read -r sofile; do
    cp "$sofile" "$ARTIFACT"
done

rm -rf "$BUILD_DIR"

if [ -f "$ARTIFACT" ]; then
    echo "[build-decoder-php85] Built: $ARTIFACT"
    php8.5 -r "echo 'PHP ' . PHP_VERSION . PHP_EOL;" 2>/dev/null || true
    php8.5 -d "extension=$ARTIFACT" -r 'phpinfo();' 2>/dev/null | grep -i "mmloader" | head -3 || true
else
    echo "ERROR: build succeeded but .so not found" >&2
    exit 1
fi
