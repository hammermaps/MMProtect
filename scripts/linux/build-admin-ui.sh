#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UI_DIR="$REPO_ROOT/src/AdminUi"

echo "=== MMProtect Admin UI Build ==="
echo "  UI source : $UI_DIR"
echo "  Output    : $REPO_ROOT/src/LicenseServer/wwwroot/admin"
echo ""

if ! command -v node &>/dev/null; then
    echo "ERROR: Node.js not found. Install from https://nodejs.org/ (>=18)" >&2
    exit 1
fi

if ! command -v npm &>/dev/null; then
    echo "ERROR: npm not found." >&2
    exit 1
fi

cd "$UI_DIR"

echo "Installing dependencies..."
npm ci

echo "Building..."
npm run build

echo ""
echo "Done. Admin UI available at /admin/ when the LicenseServer is running."
