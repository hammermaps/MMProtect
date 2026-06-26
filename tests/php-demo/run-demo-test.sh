#!/usr/bin/env bash
# =============================================================================
#  MMProtect – Demo-Projekt Testskript
#  Testet den vollständigen Flow:
#    1. Klartext-PHP ausführen
#    2. Verzeichnis mit encode-dir (Dev-Modus) verschlüsseln
#    3. Einzelne Dateien mit mmloader (dev_buildkey) ausführen
#    4. OPcache-Modus prüfen
#    5. Smoke-Test der verschlüsselten Anwendung
#    6. encode-dir Dry-Run
#    7. .mmignore Ausschluss prüfen
# =============================================================================
set -uo pipefail

# ── Pfade ──────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEMO_DIR="$REPO_ROOT/tests/php-demo"
ENCODER_DLL="$REPO_ROOT/artifacts/encoder/linux-x64/mmencoder.dll"
LOADER_SO="$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so"
LOADER_SO_85="$REPO_ROOT/artifacts/decoder/linux-x64/mmloader-php85.so"
OUT_DIR="$(mktemp -d /tmp/mmtest-demo-XXXXXX)"
MMIGNORE="$OUT_DIR/demo.mmignore"

PHP84="${PHP84:-php8.4}"
PHP85="${PHP85:-php8.5}"

# ── Farben ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; ((SKIP++)); }
sep()  { echo ""; echo "── $1 ──────────────────────────────────────────────"; }

cleanup() { rm -rf "$OUT_DIR"; }
trap cleanup EXIT

echo "========================================================"
echo "  MMProtect Demo-Projekt Testlauf"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo "  Repo:    $REPO_ROOT"
echo "  Demo:    $DEMO_DIR"
echo "  Output:  $OUT_DIR"
echo ""

# ── Voraussetzungen prüfen ─────────────────────────────────────────────────
sep "Voraussetzungen"

if [[ ! -f "$ENCODER_DLL" ]]; then
  fail "Encoder nicht gebaut: $ENCODER_DLL"
  echo "  → scripts/linux/build-encoder.sh ausführen"
  exit 1
fi
pass "Encoder vorhanden"

if [[ ! -f "$LOADER_SO" ]]; then
  fail "mmloader.so nicht gebaut: $LOADER_SO"
  echo "  → scripts/linux/build-decoder.sh ausführen"
  exit 1
fi
pass "mmloader.so vorhanden"

if ! command -v "$PHP84" &>/dev/null; then
  fail "$PHP84 nicht gefunden"
  exit 1
fi
pass "PHP 8.4: $($PHP84 --version | head -1)"

# ── Test 1: Klartext-PHP ausführen ────────────────────────────────────────
sep "Test 1: Klartext-PHP ausführen"

RESULT=$(cd "$DEMO_DIR" && "$PHP84" public/index.php 2>&1) || true
if echo "$RESULT" | grep -q "protected project code executed"; then
  pass "Klartext-Ausführung: $RESULT"
else
  fail "Klartext-Ausführung fehlgeschlagen: $RESULT"
fi

RESULT=$(cd "$DEMO_DIR" && "$PHP84" tests/smoke.php 2>&1) || true
if echo "$RESULT" | grep -q "Smoke test ok"; then
  pass "Klartext Smoke-Test: $RESULT"
else
  fail "Klartext Smoke-Test fehlgeschlagen: $RESULT"
fi

# ── Test 2: encode-dir (Dev-Modus) ────────────────────────────────────────
sep "Test 2: Verschlüsselung mit encode-dir (Dev-Modus)"

cat > "$MMIGNORE" << 'IGNORE_EOF'
# vendor/ als Klartext kopieren
+ vendor/
+ composer.json
+ composer.lock
+ config/

# Test-Skripte nicht verschlüsseln (nur public/ und src/ werden kodiert)
# → kein Ausschluss: tests/ wird standardmäßig verschlüsselt

# .mmprotect nie doppelt einschließen
.mmprotect/
IGNORE_EOF

ENCODED_DIR="$OUT_DIR/encoded"
dotnet "$ENCODER_DLL" encode-dir \
    --source "$DEMO_DIR" \
    --output "$ENCODED_DIR" \
    --mmignore "$MMIGNORE" \
    --dev 2>&1 | grep -E "^(\[DEV\]|Fertig|ERROR)" || true

if [[ -f "$ENCODED_DIR/.mmprotect/dev-buildkey.b64" ]]; then
  pass "dev-buildkey.b64 erzeugt"
else
  fail "dev-buildkey.b64 fehlt"
fi

if [[ -f "$ENCODED_DIR/.mmprotect/manifest.json" ]]; then
  pass "manifest.json erzeugt"
else
  fail "manifest.json fehlt"
fi

if [[ -f "$ENCODED_DIR/vendor/autoload.php" ]]; then
  pass "vendor/autoload.php als Klartext kopiert"
else
  fail "vendor/autoload.php fehlt im Output"
fi

# ── Test 3: MMENC1-Magic prüfen ────────────────────────────────────────────
sep "Test 3: MMENC1-Container-Format"

for PHPFILE in \
    "src/App/Application.php" \
    "src/App/Controller/HomeController.php" \
    "src/App/Service/DemoService.php" \
    "public/index.php"
do
  MAGIC=$(head -c 6 "$ENCODED_DIR/$PHPFILE" 2>/dev/null || echo "")
  if [[ "$MAGIC" == "MMENC1" ]]; then
    pass "MMENC1-Magic: $PHPFILE"
  else
    fail "Kein MMENC1-Magic in $PHPFILE (gefunden: '$MAGIC')"
  fi
done

# vendor-Dateien müssen Klartext sein
VENDOR_FIRST=$(head -c 5 "$ENCODED_DIR/vendor/autoload.php" 2>/dev/null || echo "")
if [[ "$VENDOR_FIRST" == "<?php" ]]; then
  pass "vendor/autoload.php ist Klartext (nicht verschlüsselt)"
else
  fail "vendor/autoload.php sollte Klartext sein, got: '$VENDOR_FIRST'"
fi

# ── Test 4: Verschlüsselte PHP-Dateien mit mmloader ausführen ──────────────
sep "Test 4: Ausführung mit mmloader (PHP 8.4, Dev-Modus)"

DEV_KEY="$ENCODED_DIR/.mmprotect/dev-buildkey.b64"

RESULT=$("$PHP84" \
    -d "extension=$LOADER_SO" \
    -d "mmloader.dev_mode=1" \
    -d "mmloader.dev_buildkey=$DEV_KEY" \
    "$ENCODED_DIR/public/index.php" 2>&1) || true

if echo "$RESULT" | grep -q "protected project code executed"; then
  pass "PHP 8.4 Ausführung: $RESULT"
else
  fail "PHP 8.4 Ausführung fehlgeschlagen: $RESULT"
fi

# ── Test 5: Smoke-Test der verschlüsselten Anwendung ──────────────────────
sep "Test 5: Smoke-Test (verschlüsselte Anwendung)"

RESULT=$("$PHP84" \
    -d "extension=$LOADER_SO" \
    -d "mmloader.dev_mode=1" \
    -d "mmloader.dev_buildkey=$DEV_KEY" \
    "$ENCODED_DIR/tests/smoke.php" 2>&1) || true

if echo "$RESULT" | grep -q "Smoke test ok"; then
  pass "Smoke-Test verschlüsselt: $RESULT"
else
  fail "Smoke-Test fehlgeschlagen: $RESULT"
fi

# ── Test 6: OPcache-Modus ─────────────────────────────────────────────────
sep "Test 6: mmloader mit OPcache (PHP 8.4)"

RESULT=$("$PHP84" \
    -d "zend_extension=opcache.so" \
    -d "opcache.enable_cli=1" \
    -d "extension=$LOADER_SO" \
    -d "mmloader.dev_mode=1" \
    -d "mmloader.dev_buildkey=$DEV_KEY" \
    "$ENCODED_DIR/public/index.php" 2>&1) || true

if echo "$RESULT" | grep -q "protected project code executed"; then
  pass "OPcache + mmloader PHP 8.4: OK"
else
  fail "OPcache + mmloader fehlgeschlagen: $RESULT"
fi

# ── Test 7: PHP 8.5 (optional) ────────────────────────────────────────────
sep "Test 7: PHP 8.5 (optional)"

if [[ ! -f "$LOADER_SO_85" ]]; then
  skip "mmloader-php85.so nicht gebaut → sudo apt install php8.5-dev && scripts/linux/build-decoder-php85.sh"
elif ! command -v "$PHP85" &>/dev/null; then
  skip "$PHP85 nicht gefunden"
else
  RESULT=$("$PHP85" \
      -d "extension=$LOADER_SO_85" \
      -d "mmloader.dev_mode=1" \
      -d "mmloader.dev_buildkey=$DEV_KEY" \
      "$ENCODED_DIR/public/index.php" 2>&1) || true

  if echo "$RESULT" | grep -q "protected project code executed"; then
    pass "PHP 8.5 Ausführung: $RESULT"
  else
    fail "PHP 8.5 Ausführung fehlgeschlagen: $RESULT"
  fi
fi

# ── Test 8: Dry-Run erzeugt keinen Output ─────────────────────────────────
sep "Test 8: Dry-Run (--dry-run)"

DRYRUN_DIR="$OUT_DIR/dryrun"
dotnet "$ENCODER_DLL" encode-dir \
    --source "$DEMO_DIR" \
    --output "$DRYRUN_DIR" \
    --mmignore "$MMIGNORE" \
    --dev --dry-run 2>&1 | grep -E "^(\[DRY-RUN\]|ERROR)" || true

if [[ ! -d "$DRYRUN_DIR" ]]; then
  pass "Dry-Run hat kein Output-Verzeichnis erzeugt"
else
  fail "Dry-Run hat unerwarteterweise $DRYRUN_DIR erzeugt"
fi

# ── Test 9: .mmignore Ausschluss prüfen ───────────────────────────────────
sep "Test 9: .mmignore Ausschluss"

# Encode mit Ausschluss von config/
EXCL_MMIGNORE="$OUT_DIR/excl.mmignore"
cat > "$EXCL_MMIGNORE" << 'IGNORE_EOF'
+ vendor/
+ composer.json
config/
IGNORE_EOF

EXCL_DIR="$OUT_DIR/excl"
dotnet "$ENCODER_DLL" encode-dir \
    --source "$DEMO_DIR" \
    --output "$EXCL_DIR" \
    --mmignore "$EXCL_MMIGNORE" \
    --dev 2>/dev/null || true

if [[ ! -f "$EXCL_DIR/config/app.php" ]]; then
  pass ".mmignore Ausschluss: config/ nicht im Output"
else
  fail "config/app.php sollte ausgeschlossen sein, ist aber im Output"
fi

if [[ -f "$EXCL_DIR/src/App/Application.php" ]]; then
  MAGIC=$(head -c 6 "$EXCL_DIR/src/App/Application.php")
  if [[ "$MAGIC" == "MMENC1" ]]; then
    pass "src/ trotzdem verschlüsselt"
  else
    fail "src/App/Application.php sollte MMENC1 sein"
  fi
else
  fail "src/App/Application.php fehlt im Output"
fi

# ── Test 10: Klartext-Datei wird NICHT als MMENC1 geladen ─────────────────
sep "Test 10: Klartext-PHP mit aktivem mmloader"

PLAIN_TEST=$(mktemp /tmp/mmtest-plain-XXXXXX.php)
echo '<?php echo "plain ok\n";' > "$PLAIN_TEST"

RESULT=$("$PHP84" \
    -d "extension=$LOADER_SO" \
    -d "mmloader.dev_mode=1" \
    -d "mmloader.dev_buildkey=$DEV_KEY" \
    "$PLAIN_TEST" 2>&1) || true
rm -f "$PLAIN_TEST"

if echo "$RESULT" | grep -q "plain ok"; then
  pass "Klartext-PHP läuft unverändert durch mmloader"
else
  fail "Klartext-PHP fehlgeschlagen: $RESULT"
fi

# ── Ergebnis ───────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
printf "  Ergebnis: %d bestanden" "$PASS"
[[ $FAIL -gt 0 ]] && printf ", ${RED}%d fehlgeschlagen${NC}" "$FAIL"
[[ $SKIP -gt 0 ]] && printf ", ${YELLOW}%d übersprungen${NC}" "$SKIP"
echo ""
echo "========================================================"

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}ALLE TESTS BESTANDEN${NC}"
  echo "========================================================"
  exit 0
else
  echo -e "  ${RED}FEHLER — $FAIL Test(s) fehlgeschlagen${NC}"
  echo "========================================================"
  exit 1
fi
