#!/usr/bin/env bash
# run-fuzz-test.sh — Corpus-based fuzz tests for the MMENC1 decoder.
#
# Generates a set of purposefully malformed MMENC1 files, loads each one
# through PHP + mmloader (dev_mode, no network), and verifies that:
#   - PHP exits without a crash signal (no SIGSEGV / SIGABRT / SIGBUS)
#   - PHP does NOT execute a "FUZZ_DECRYPTED" marker (no bypass)
#
# Usage:
#   bash tests/decoder-loader/run-fuzz-test.sh [--ext84 PATH] [--ext85 PATH]
#
# Prerequisites: mmloader-dev.so built (scripts/linux/build-decoder-dev.sh)

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# ── Defaults ──────────────────────────────────────────────────────────────────

PHP84=$(command -v php8.4 2>/dev/null || command -v php 2>/dev/null || true)
EXT84="artifacts/decoder/linux-x64/mmloader-dev.so"
PHP85=$(command -v php8.5 2>/dev/null || true)
EXT85="artifacts/decoder/linux-x64/mmloader-dev-php85.so"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ext84) EXT84="$2"; shift 2 ;;
        --ext85) EXT85="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

PASS=0; FAIL=0; SKIP=0
CORPUS_DIR="$(mktemp -d /tmp/mmfuzz_XXXXXX)"
CACHE_DIR="$(mktemp -d /tmp/mmfuzz_cache_XXXXXX)"
trap 'rm -rf "$CORPUS_DIR" "$CACHE_DIR"' EXIT

# ── Helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "  [PASS] $1"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $1"; ((FAIL++)) || true; }
skip() { echo "  [SKIP] $1"; ((SKIP++)) || true; }

# Run PHP with mmloader in dev_mode (no network required).
# Returns:
#   0 = PHP exited without crash and without bypass
#   1 = crash signal
#   2 = timeout
#   3 = bypass (FUZZ_DECRYPTED appeared in output)
run_php() {
    local ext="$1" phpbin="$2" file="$3"
    local out rc=0

    out=$(timeout 4 "$phpbin" \
        -d "extension=$ext" \
        -d "mmloader.enabled=1" \
        -d "mmloader.dev_mode=1" \
        -d "mmloader.dev_buildkey=/nonexistent/dev-buildkey.b64" \
        -d "mmloader.cache_dir=$CACHE_DIR" \
        -d "error_reporting=E_ALL" \
        -d "display_errors=stderr" \
        -r "@include '$file'; echo 'PHP_OK';" \
        2>&1) || rc=$?

    case $rc in
        0)   ;;
        124) echo "    TIMEOUT: $(basename "$file")"; return 2 ;;
        139|134|135|136|132)
             echo "    CRASH (signal, rc=$rc): $(basename "$file")"; return 1 ;;
        *)   ;; # PHP fatal error → rc=255 or 1, that's fine
    esac

    if echo "$out" | grep -q "FUZZ_DECRYPTED"; then
        echo "    BYPASS: $(basename "$file")"; return 3
    fi
    return 0
}

# ── Corpus generation ─────────────────────────────────────────────────────────

# All files must be created BEFORE the run loop.

mmenc1_file() {
    local name="$1" header_json="$2"
    local payload="${3:-$(printf 'X%.0s' {1..64})}"
    local file="$CORPUS_DIR/$name.php"
    local hlen
    hlen=$(printf '%s' "$header_json" | wc -c)
    printf 'MMENC1\n%08d\n%s%s' "$hlen" "$header_json" "$payload" > "$file"
    echo "$file"
}

VALID_HDR='{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","buildId":"build_fuzz","fileId":"file_fuzz","projectId":"proj","customerId":"cust","licenseId":"lic","relativePath":"src/fuzz.php","pathHash":"sha256:aabbccdd","plainHash":"sha256:aabbccdd","cipherHash":"sha256:aabbccdd","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","kdf":"HKDF-SHA256","manifestHash":"sha256:aabb","signature":"MEQCIA=="}'

declare -A CASES

# Magic-byte failures
CASES["01_wrong_magic"]="$(printf 'WRONGM\n00000020\n{"algorithm":"AES-256-GCM"}XXXXXXXXXXXXXXXXXXXXXXXX' > "$CORPUS_DIR/01_wrong_magic.php"; echo "$CORPUS_DIR/01_wrong_magic.php")"
CASES["02_no_magic"]="$(printf 'plain PHP content' > "$CORPUS_DIR/02_no_magic.php"; echo "$CORPUS_DIR/02_no_magic.php")"
CASES["03_empty_file"]="$(touch "$CORPUS_DIR/03_empty.php"; echo "$CORPUS_DIR/03_empty.php")"

# Header-length field failures
CASES["04_only_magic"]="$(printf 'MMENC1\n' > "$CORPUS_DIR/04_only_magic.php"; echo "$CORPUS_DIR/04_only_magic.php")"
CASES["05_zero_header_len"]="$(printf 'MMENC1\n00000000\n%s' "$VALID_HDR" > "$CORPUS_DIR/05_zero_hlen.php"; echo "$CORPUS_DIR/05_zero_hlen.php")"
CASES["06_huge_header_len"]="$(printf 'MMENC1\n99999999\nXX' > "$CORPUS_DIR/06_huge_hlen.php"; echo "$CORPUS_DIR/06_huge_hlen.php")"
CASES["07_nondigit_len_field"]="$(printf 'MMENC1\nABCDEFGH\n%s' "$VALID_HDR" > "$CORPUS_DIR/07_nondigit_len.php"; echo "$CORPUS_DIR/07_nondigit_len.php")"
CASES["08_truncated_at_7"]="$(printf 'MMENC1\n' | head -c 7 > "$CORPUS_DIR/08_trunc_7.php"; echo "$CORPUS_DIR/08_trunc_7.php")"
CASES["09_truncated_at_50"]="$(printf 'MMENC1\n00000500\n%s' "$VALID_HDR" | head -c 50 > "$CORPUS_DIR/09_trunc_50.php"; echo "$CORPUS_DIR/09_trunc_50.php")"

# JSON header failures
CASES["10_non_json"]="$(mmenc1_file '10_non_json' 'THIS IS NOT JSON AT ALL')"
CASES["11_empty_json"]="$(mmenc1_file '11_empty_json' '{}')"
CASES["12_json_array"]="$(mmenc1_file '12_json_array' '[1,2,3]')"
CASES["13_truncated_json"]="$(mmenc1_file '13_trunc_json' '{"algorithm":"AES-256')"

# Format version failures
CASES["14_future_version"]="$(mmenc1_file '14_future_ver' '{"format":"MMENC1","formatVersion":999,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"
CASES["15_version_zero"]="$(mmenc1_file '15_ver_zero' '{"format":"MMENC1","formatVersion":0,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"

# Missing required fields
CASES["16_missing_nonce"]="$(mmenc1_file '16_no_nonce' '{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"
CASES["17_missing_tag"]="$(mmenc1_file '17_no_tag' '{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"
CASES["18_missing_buildid"]="$(mmenc1_file '18_no_buildid' '{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"

# Algorithm failures
CASES["19_bad_algo"]="$(mmenc1_file '19_bad_algo' '{"format":"MMENC1","formatVersion":1,"algorithm":"RSA-2048","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"

# Nonce / tag length failures
CASES["20_short_nonce"]="$(mmenc1_file '20_short_nonce' '{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAA","tag":"AAAAAAAAAAAAAAAAAAAAAA==","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"
CASES["21_short_tag"]="$(mmenc1_file '21_short_tag' '{"format":"MMENC1","formatVersion":1,"algorithm":"AES-256-GCM","buildId":"b","fileId":"f","pathHash":"sha256:aa","nonce":"AAAAAAAAAAAAAAAA","tag":"AAAA","signature":"AA==","manifestHash":"","cipherHash":"sha256:00"}')"

# Malformed ciphertext (correct header structure, garbage payload)
CASES["22_zero_ciphertext"]="$(mmenc1_file '22_zero_ct' "$VALID_HDR" "$(dd if=/dev/zero bs=64 count=1 2>/dev/null)")"
CASES["23_random_ciphertext"]="$(mmenc1_file '23_rand_ct' "$VALID_HDR" "$(dd if=/dev/urandom bs=64 count=1 2>/dev/null)")"
CASES["24_empty_ciphertext"]="$(mmenc1_file '24_empty_ct' "$VALID_HDR" '')"

# Large inputs (potential buffer overread or allocation failure)
CASES["25_large_buildid"]="$(python3 -c "
import json,sys
h=json.dumps({'format':'MMENC1','formatVersion':1,'algorithm':'AES-256-GCM',
  'buildId':'B'*8192,'fileId':'F'*8192,'pathHash':'sha256:aa',
  'nonce':'AAAAAAAAAAAAAAAA','tag':'AAAAAAAAAAAAAAAAAAAAAA==',
  'signature':'AA==','manifestHash':'','cipherHash':'sha256:00'},separators=(',',':'))
b=h.encode()
sys.stdout.buffer.write(b'MMENC1\n'+f'{len(b):08d}\n'.encode()+b+b'X'*64)
" > "$CORPUS_DIR/25_large_buildid.php" 2>/dev/null; echo "$CORPUS_DIR/25_large_buildid.php")"

# Null bytes in JSON
CASES["26_null_in_json"]="$(printf 'MMENC1\n00000030\n{"algorithm":"AES-\x00256-GCM"}XXXXXXXXXXXXXXXXXXXXXXXXXX' > "$CORPUS_DIR/26_null_json.php"; echo "$CORPUS_DIR/26_null_json.php")"

# All-zero file after magic (header len = zero bytes decoded)
CASES["27_zeros_after_magic"]="$(printf 'MMENC1\n\x00\x00\x00\x00\x00\x00\x00\x00\n' > "$CORPUS_DIR/27_zeros.php"; echo "$CORPUS_DIR/27_zeros.php")"

# ── Run corpus through PHP + mmloader ─────────────────────────────────────────

echo "========================================================="
echo "MMENC1 Decoder Fuzz Test (${#CASES[@]} corpus cases)"
echo "========================================================="

run_all() {
    local ext="$1" phpbin="$2" label="$3"
    echo ""
    echo "--- $label ---"
    local -i p=0 f=0
    for name in $(printf '%s\n' "${!CASES[@]}" | sort); do
        local file="${CASES[$name]}"
        [[ -f "$file" ]] || { skip "$name (file not created)"; continue; }
        local rv=0
        run_php "$ext" "$phpbin" "$file" || rv=$?
        case $rv in
            0) ok "$name"; ((p++)) || true ;;
            1) fail "CRASH: $name"; ((f++)) || true ;;
            2) fail "TIMEOUT: $name"; ((f++)) || true ;;
            3) fail "BYPASS: $name"; ((f++)) || true ;;
        esac
    done
    echo "  Sub-total: $p passed, $f failed"
    PASS=$((PASS + p)); FAIL=$((FAIL + f))
}

if [[ -n "$PHP84" && -f "$EXT84" ]]; then
    run_all "$EXT84" "$PHP84" "PHP 8.4 + mmloader-dev"
else
    skip "PHP 8.4 dev ext not available (EXT84=$EXT84)"
    echo "  Hint: run scripts/linux/build-decoder-dev.sh to build mmloader-dev.so"
fi

if [[ -n "$PHP85" && -f "$EXT85" ]]; then
    run_all "$EXT85" "$PHP85" "PHP 8.5 + mmloader-dev"
else
    skip "PHP 8.5 dev ext not available"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "========================================================="
echo "Fuzz Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================================="

if [[ $FAIL -gt 0 ]]; then
    echo "FAILURES detected — check output above for crash/bypass details"
    exit 1
fi
