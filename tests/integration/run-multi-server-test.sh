#!/usr/bin/env bash
# MMProtect Multi-Server Integration Test
#
# Startet zwei unabhängige LicenseServer-Instanzen auf verschiedenen Ports,
# encodiert zwei Projekte (jeweils mit eingebetteter Server-URL im MMENC1-Header)
# und überprüft, dass der mmloader die richtige Instanz kontaktiert.
#
# Getestete Szenarien:
#   A. Projekt A  → Server A (Port 15390) — Header-URL wird vom Loader verwendet
#   B. Projekt B  → Server B (Port 15391) — Header-URL wird vom Loader verwendet
#   C. Cross-Isolation: Lease von A ist nur in DB-A, Lease von B nur in DB-B
#   D. Header schlägt INI: INI zeigt auf Server A, Projekt B hat Header→Server B
#      → Loader kontaktiert trotzdem Server B (Header hat Vorrang)
#
# Voraussetzungen:
#   - dotnet 8 SDK, php8.4, openssl, sqlite3, python3
#   - mmloader.so gebaut (artifacts/decoder/linux-x64/mmloader.so)
#
# Aufruf:
#   tests/integration/run-multi-server-test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d /tmp/mmtest-multiserver-XXXXXX)"
KEY_DIR="$WORK_DIR/keys"
DB_A="$WORK_DIR/server_a.db"
DB_B="$WORK_DIR/server_b.db"
LOG_A="$WORK_DIR/server_a.log"
LOG_B="$WORK_DIR/server_b.log"
PORT_A=15390
PORT_B=15391
PID_A=""
PID_B=""
PASS=0; FAIL=0

EXT84="${1:-$REPO_ROOT/artifacts/decoder/linux-x64/mmloader.so}"
PHP84="php8.4"
DEMO_SRC="$REPO_ROOT/tests/php-demo"
SERVER_EXE="$REPO_ROOT/src/LicenseServer/bin/Release/net8.0/MmProtect.LicenseServer.dll"
SERVER_CONTENT="$(dirname "$(realpath "$SERVER_EXE" 2>/dev/null || echo "$SERVER_EXE")")"

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
sep()  { echo; echo "── $* ──────────────────────────────────────────"; }

# Liest ein Feld aus dem MMENC1-JSON-Header einer PHP-Datei.
mmenc1_field() {
    python3 - "$1" "$2" << 'PYEOF'
import sys, json
try:
    with open(sys.argv[1], 'rb') as f:
        f.read(7)
        hlen = int(f.read(8))
        f.read(1)
        h = json.loads(f.read(hlen))
    print(h.get(sys.argv[2], ""))
except Exception as e:
    print("ERROR:" + str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Startet eine LicenseServer-Instanz und wartet bis sie antwortet.
start_server() {
    local port="$1" db="$2" log="$3"
    ASPNETCORE_ENVIRONMENT=Integration \
    ASPNETCORE_URLS="http://127.0.0.1:$port" \
    dotnet "$SERVER_EXE" \
        --contentRoot "$SERVER_CONTENT" \
        --DatabaseProvider sqlite \
        --ConnectionStrings:Sqlite "Data Source=$db" \
        --Security:SigningPrivateKeyFile "$KEY_DIR/signing-private.pem" \
        --Security:LeaseTtlMinutes 60 \
        --Security:GracePeriodDays 3 \
        >"$log" 2>&1 &
    local pid=$!
    for i in $(seq 1 40); do
        if curl -sf "http://127.0.0.1:$port/health" &>/dev/null; then
            echo "$pid"
            return 0
        fi
        sleep 0.3
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: Server (port $port) exited. Log:" >&2
            cat "$log" >&2
            return 1
        fi
    done
    echo "ERROR: Server (port $port) did not start in time" >&2
    return 1
}

cleanup() {
    [ -n "$PID_A" ] && kill "$PID_A" 2>/dev/null || true
    [ -n "$PID_B" ] && kill "$PID_B" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "========================================================"
echo " MMProtect Multi-Server Integration Test"
echo "========================================================"
echo "  Repo      : $REPO_ROOT"
echo "  Work      : $WORK_DIR"
echo "  Server A  : http://127.0.0.1:$PORT_A  (DB: $DB_A)"
echo "  Server B  : http://127.0.0.1:$PORT_B  (DB: $DB_B)"
echo "  Ext 8.4   : $EXT84"
echo

for cmd in dotnet "$PHP84" openssl sqlite3 python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found in PATH" >&2; exit 1
    fi
done
if [ ! -f "$EXT84" ]; then
    echo "ERROR: mmloader.so not found at $EXT84" >&2; exit 1
fi

# ── Step 1: Signing Keys ──────────────────────────────────────────────────
sep "Step 1: ECDSA-P256 Signing Keys"
mkdir -p "$KEY_DIR"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
    -out "$KEY_DIR/signing-private.pem" 2>/dev/null
openssl pkey -in "$KEY_DIR/signing-private.pem" -pubout \
    -out "$KEY_DIR/signing-public.pem"
chmod 600 "$KEY_DIR/signing-private.pem"
echo "  OK — $KEY_DIR/"

# ── Step 2: Datenbanken ──────────────────────────────────────────────────
sep "Step 2: SQLite Databases (A + B)"
sqlite3 "$DB_A" < "$REPO_ROOT/database/sqlite/schema.sql"
sqlite3 "$DB_B" < "$REPO_ROOT/database/sqlite/schema.sql"
echo "  OK — DB-A: $DB_A"
echo "  OK — DB-B: $DB_B"

# ── Step 3: Build LicenseServer ───────────────────────────────────────────
sep "Step 3: Build LicenseServer"
dotnet build -c Release "$REPO_ROOT/src/LicenseServer/LicenseServer.csproj" \
    -nologo -v q 2>&1 | tail -3
SERVER_CONTENT="$(dirname "$(realpath "$SERVER_EXE")")"

# ── Step 4: Server A starten ──────────────────────────────────────────────
sep "Step 4: Start Server A (port $PORT_A)"
PID_A=$(start_server "$PORT_A" "$DB_A" "$LOG_A")
echo "  OK — Server A läuft (PID $PID_A)"

# ── Step 5: Server B starten ──────────────────────────────────────────────
sep "Step 5: Start Server B (port $PORT_B)"
PID_B=$(start_server "$PORT_B" "$DB_B" "$LOG_B")
echo "  OK — Server B läuft (PID $PID_B)"

# ── Step 6: Encoder bauen ────────────────────────────────────────────────
sep "Step 6: Build Encoder"
dotnet build -c Release "$REPO_ROOT/src/EncoderCli/EncoderCli.csproj" \
    -nologo -v q 2>&1 | tail -3
echo "  OK"

# ── Encoder-Config-Template ───────────────────────────────────────────────
make_encoder_config() {
    local port="$1" output_root="$2" config_out="$3" project_key="$4" license_key="$5"
    sed \
        -e "s|__SIGNING_PRIV__|$KEY_DIR/signing-private.pem|g" \
        -e "s|__SIGNING_PUB__|$KEY_DIR/signing-public.pem|g" \
        -e "s|__SOURCE_ROOT__|$DEMO_SRC|g" \
        -e "s|__OUTPUT_ROOT__|$output_root|g" \
        -e "s|__SERVER_PORT__|$port|g" \
        -e "s|__PROJECT_KEY__|$project_key|g" \
        -e "s|__LICENSE_KEY__|$license_key|g" \
        "$REPO_ROOT/tests/integration/encoder.config.multiserver.json" \
        > "$config_out"
}

# ── Step 7: Projekt A encodieren (Server A) ──────────────────────────────
sep "Step 7: Encode Project A → Server A (port $PORT_A)"
OUTPUT_A="$WORK_DIR/encoded_a"
CONFIG_A="$WORK_DIR/config_a.json"
mkdir -p "$OUTPUT_A"
make_encoder_config "$PORT_A" "$OUTPUT_A" "$CONFIG_A" "project-server-a" "MM-MSTEST-A-001"

MM_ENCODER_API_KEY="dev-encoder-api-key-change-me" \
dotnet run --project "$REPO_ROOT/src/EncoderCli/EncoderCli.csproj" \
    -c Release --no-build -- \
    encode --config "$CONFIG_A" --project project-server-a 2>&1 | tail -5

if [ -f "$OUTPUT_A/.mmprotect/manifest.json" ]; then
    ok "Project A: manifest.json erzeugt"
else
    fail "Project A: manifest.json fehlt"
fi

# ── Step 8: Projekt B encodieren (Server B) ──────────────────────────────
sep "Step 8: Encode Project B → Server B (port $PORT_B)"
OUTPUT_B="$WORK_DIR/encoded_b"
CONFIG_B="$WORK_DIR/config_b.json"
mkdir -p "$OUTPUT_B"
make_encoder_config "$PORT_B" "$OUTPUT_B" "$CONFIG_B" "project-server-b" "MM-MSTEST-B-001"

MM_ENCODER_API_KEY="dev-encoder-api-key-change-me" \
dotnet run --project "$REPO_ROOT/src/EncoderCli/EncoderCli.csproj" \
    -c Release --no-build -- \
    encode --config "$CONFIG_B" --project project-server-b 2>&1 | tail -5

if [ -f "$OUTPUT_B/.mmprotect/manifest.json" ]; then
    ok "Project B: manifest.json erzeugt"
else
    fail "Project B: manifest.json fehlt"
fi

# ── Step 9: Header-Felder prüfen ─────────────────────────────────────────
sep "Step 9: MMENC1 Header licenseServer-Felder"

FILE_A=$(find "$OUTPUT_A/src" -name "*.php" | head -1)
FILE_B=$(find "$OUTPUT_B/src" -name "*.php" | head -1)

LS_A=$(mmenc1_field "$FILE_A" "licenseServer" 2>/dev/null || echo "ERROR")
LS_B=$(mmenc1_field "$FILE_B" "licenseServer" 2>/dev/null || echo "ERROR")

if [[ "$LS_A" == "http://127.0.0.1:$PORT_A" ]]; then
    ok "Project A: Header licenseServer=http://127.0.0.1:$PORT_A"
else
    fail "Project A: Header licenseServer falsch: '$LS_A'"
fi

if [[ "$LS_B" == "http://127.0.0.1:$PORT_B" ]]; then
    ok "Project B: Header licenseServer=http://127.0.0.1:$PORT_B"
else
    fail "Project B: Header licenseServer falsch: '$LS_B'"
fi

# ── Step 10: Szenario A – Loader holt Lease von Server A ─────────────────
sep "Step 10: PHP-Ausführung Projekt A → Server A"
CACHE_A="$WORK_DIR/cache_a"
mkdir -p "$CACHE_A"

# Kein mmloader.license_server gesetzt — Loader muss URL aus Header lesen
RESULT_A=$("$PHP84" \
    -d "extension=$EXT84" \
    -d "mmloader.manifest_file=$OUTPUT_A/.mmprotect/manifest.json" \
    -d "mmloader.license_file=$OUTPUT_A/.mmprotect/license.json" \
    -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
    -d "mmloader.dev_mode=0" \
    -d "mmloader.cache_dir=$CACHE_A" \
    "$OUTPUT_A/public/index.php" 2>&1) || true

if echo "$RESULT_A" | grep -qi "MMProtect Demo"; then
    ok "Szenario A: Ausführung OK — Loader hat Server A kontaktiert"
else
    fail "Szenario A: Ausführung fehlgeschlagen: $RESULT_A"
fi

# ── Step 11: Szenario B – Loader holt Lease von Server B ─────────────────
sep "Step 11: PHP-Ausführung Projekt B → Server B"
CACHE_B="$WORK_DIR/cache_b"
mkdir -p "$CACHE_B"

RESULT_B=$("$PHP84" \
    -d "extension=$EXT84" \
    -d "mmloader.manifest_file=$OUTPUT_B/.mmprotect/manifest.json" \
    -d "mmloader.license_file=$OUTPUT_B/.mmprotect/license.json" \
    -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
    -d "mmloader.dev_mode=0" \
    -d "mmloader.cache_dir=$CACHE_B" \
    "$OUTPUT_B/public/index.php" 2>&1) || true

if echo "$RESULT_B" | grep -qi "MMProtect Demo"; then
    ok "Szenario B: Ausführung OK — Loader hat Server B kontaktiert"
else
    fail "Szenario B: Ausführung fehlgeschlagen: $RESULT_B"
fi

# ── Step 12: Cross-Isolation – Leases in richtigen DBs ───────────────────
sep "Step 12: Cross-Server-Isolation"

sleep 0.5  # kurz warten damit Commits durch sind

LEASE_A=$(sqlite3 "$DB_A" "SELECT COUNT(*) FROM runtime_leases;" 2>/dev/null || echo "0")
LEASE_B=$(sqlite3 "$DB_B" "SELECT COUNT(*) FROM runtime_leases;" 2>/dev/null || echo "0")
BUILD_A=$(sqlite3 "$DB_A" "SELECT build_id FROM builds LIMIT 1;" 2>/dev/null || echo "")
BUILD_B=$(sqlite3 "$DB_B" "SELECT build_id FROM builds LIMIT 1;" 2>/dev/null || echo "")

echo "  DB-A: builds=$(sqlite3 "$DB_A" 'SELECT COUNT(*) FROM builds;'), leases=$LEASE_A"
echo "  DB-B: builds=$(sqlite3 "$DB_B" 'SELECT COUNT(*) FROM builds;'), leases=$LEASE_B"

if [ "$LEASE_A" -gt 0 ]; then
    ok "DB-A enthält $LEASE_A Lease(s) von Projekt A"
else
    fail "DB-A: keine Leases — Server A wurde nicht kontaktiert"
fi

if [ "$LEASE_B" -gt 0 ]; then
    ok "DB-B enthält $LEASE_B Lease(s) von Projekt B"
else
    fail "DB-B: keine Leases — Server B wurde nicht kontaktiert"
fi

# Build-IDs dürfen sich nicht in der jeweils anderen DB befinden
if [ -n "$BUILD_A" ] && [ -n "$BUILD_B" ]; then
    CROSS_A=$(sqlite3 "$DB_B" "SELECT COUNT(*) FROM builds WHERE build_id='$BUILD_A';" 2>/dev/null || echo "0")
    CROSS_B=$(sqlite3 "$DB_A" "SELECT COUNT(*) FROM builds WHERE build_id='$BUILD_B';" 2>/dev/null || echo "0")

    if [ "$CROSS_A" -eq 0 ]; then
        ok "Isolation: Build von Projekt A ist NICHT in DB-B"
    else
        fail "Isolation: Build von Projekt A ist fälschlicherweise in DB-B"
    fi

    if [ "$CROSS_B" -eq 0 ]; then
        ok "Isolation: Build von Projekt B ist NICHT in DB-A"
    else
        fail "Isolation: Build von Projekt B ist fälschlicherweise in DB-A"
    fi
fi

# ── Step 13: Header schlägt INI – Projekt B mit INI→Server A ─────────────
sep "Step 13: Header-URL hat Vorrang vor INI (Projekt B mit INI→Server A)"

# Cache leeren damit ein echter Lease-Request ausgelöst wird
CACHE_PRIO="$WORK_DIR/cache_prio"
mkdir -p "$CACHE_PRIO"

RESULT_PRIO=$("$PHP84" \
    -d "extension=$EXT84" \
    -d "mmloader.license_server=http://127.0.0.1:$PORT_A" \
    -d "mmloader.manifest_file=$OUTPUT_B/.mmprotect/manifest.json" \
    -d "mmloader.license_file=$OUTPUT_B/.mmprotect/license.json" \
    -d "mmloader.signing_public_key_file=$KEY_DIR/signing-public.pem" \
    -d "mmloader.dev_mode=0" \
    -d "mmloader.cache_dir=$CACHE_PRIO" \
    "$OUTPUT_B/public/index.php" 2>&1) || true

# Ausführung muss trotzdem funktionieren, weil der Header Server B einsetzt
if echo "$RESULT_PRIO" | grep -qi "MMProtect Demo"; then
    ok "Header-Vorrang: Projekt B läuft trotz INI→Server A (Header→Server B gewinnt)"
else
    fail "Header-Vorrang: Ausführung fehlgeschlagen: $RESULT_PRIO"
fi

# DB-A darf keinen neuen Lease von diesem Request enthalten
sleep 0.3
LEASE_A_AFTER=$(sqlite3 "$DB_A" "SELECT COUNT(*) FROM runtime_leases;" 2>/dev/null || echo "0")
LEASE_B_AFTER=$(sqlite3 "$DB_B" "SELECT COUNT(*) FROM runtime_leases;" 2>/dev/null || echo "0")

if [ "$LEASE_A_AFTER" -eq "$LEASE_A" ]; then
    ok "Header-Vorrang: Server A hat KEINEN neuen Lease ausgestellt (INI wurde ignoriert)"
else
    fail "Header-Vorrang: Server A hat fälschlicherweise einen neuen Lease ausgestellt"
fi

if [ "$LEASE_B_AFTER" -gt "$LEASE_B" ]; then
    ok "Header-Vorrang: Server B hat neuen Lease für Projekt B ausgestellt"
else
    fail "Header-Vorrang: Server B hat keinen Lease ausgestellt (Header-URL nicht verwendet?)"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo
echo "========================================================"
printf " Multi-Server Test Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "========================================================"
if [ $FAIL -eq 0 ]; then
    echo " ALL TESTS PASSED"
    echo "========================================================"
    exit 0
else
    echo " $FAIL TEST(S) FAILED"
    echo
    echo "Server A log (tail):"
    tail -15 "$LOG_A" 2>/dev/null || true
    echo
    echo "Server B log (tail):"
    tail -15 "$LOG_B" 2>/dev/null || true
    echo "========================================================"
    exit 1
fi
