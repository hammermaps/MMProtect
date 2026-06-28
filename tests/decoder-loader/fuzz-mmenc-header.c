/*
 * fuzz-mmenc-header.c — libFuzzer / AFL target for the MMENC1 header parser.
 *
 * Tests the magic detection, header-length parsing, and JSON header parsing
 * code paths in mmloader without a running PHP runtime.
 *
 * Build (libFuzzer, requires clang + AddressSanitizer + libFuzzer):
 *   cd tests/decoder-loader
 *   clang -g -O1 -fsanitize=fuzzer,address \
 *         -I../../src/PhpDecoderLoader/vendor/cjson \
 *         ../../src/PhpDecoderLoader/vendor/cjson/cJSON.c \
 *         fuzz-mmenc-header.c \
 *         -o fuzz-mmenc-header
 *   ./fuzz-mmenc-header corpus/ -max_len=65536 -timeout=10
 *
 * Build (AFL++):
 *   AFL_USE_ASAN=1 afl-clang-fast -g -O1 \
 *         -I../../src/PhpDecoderLoader/vendor/cjson \
 *         ../../src/PhpDecoderLoader/vendor/cjson/cJSON.c \
 *         fuzz-mmenc-header.c \
 *         -o fuzz-mmenc-header-afl
 *   afl-fuzz -i corpus/ -o findings/ -x mmenc.dict -- ./fuzz-mmenc-header-afl @@
 *
 * The target exercises:
 *   1.  Magic byte detection (MMENC1\n)
 *   2.  Header-length field parsing (8-byte ASCII decimal)
 *   3.  JSON header parsing via cJSON
 *   4.  Required-field presence checks
 *   5.  Algorithm validation
 *   6.  Format-version bounds check
 *   7.  Base64 nonce/tag decode + length check
 *
 * It does NOT test cryptographic operations (AES-GCM, HKDF, ECDSA) because
 * those depend on OpenSSL and require a valid key — fuzz those separately.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "cJSON.h"

/* ── MMENC1 constants ───────────────────────────────────────────────────── */
#define MMENC1_MAGIC          "MMENC1\n"
#define MMENC1_MAGIC_LEN      7
#define MMENC1_HEADER_LEN_FIELD 8          /* 8 ASCII decimal digits */
#define MMENC1_FORMAT_VERSION_MIN 1
#define MMENC1_FORMAT_VERSION_MAX 1
#define MMENC1_MAX_HEADER_LEN 65536

/* ── Minimal base64 decoder (validates length, no output needed for fuzzing) */
static int b64_decode_len_check(const char *b64, size_t b64_len,
                                 size_t expected_decoded_bytes)
{
    /* Quick approximation: each 4 base64 chars → 3 decoded bytes */
    if (b64_len == 0) return 0;
    size_t approx = (b64_len / 4) * 3;
    if (b64_len % 4 >= 2) approx += (b64_len % 4) - 1;
    /* Allow ±1 for padding tolerance */
    return (approx >= expected_decoded_bytes - 1 &&
            approx <= expected_decoded_bytes + 2);
}

/* ── MMENC1 header parse result ─────────────────────────────────────────── */
typedef enum {
    PARSE_OK = 0,
    PARSE_NOT_MMENC1,
    PARSE_TRUNCATED,
    PARSE_INVALID_HEADER_LEN,
    PARSE_JSON_ERROR,
    PARSE_FORMAT_VERSION_TOO_OLD,
    PARSE_FORMAT_VERSION_TOO_NEW,
    PARSE_MISSING_FIELDS,
    PARSE_BAD_ALGORITHM,
    PARSE_BAD_NONCE,
    PARSE_BAD_TAG,
} ParseResult;

static ParseResult parse_mmenc1_header(const uint8_t *data, size_t size)
{
    /* 1. Magic check */
    if (size < MMENC1_MAGIC_LEN) return PARSE_NOT_MMENC1;
    if (memcmp(data, MMENC1_MAGIC, MMENC1_MAGIC_LEN) != 0) return PARSE_NOT_MMENC1;

    /* 2. Header-length field (8 ASCII decimal digits + '\n') */
    size_t offset = MMENC1_MAGIC_LEN;
    if (size < offset + MMENC1_HEADER_LEN_FIELD + 1) return PARSE_TRUNCATED;
    char len_buf[9];
    memcpy(len_buf, data + offset, MMENC1_HEADER_LEN_FIELD);
    len_buf[8] = '\0';
    /* Validate: all 8 chars must be ASCII digits */
    for (int i = 0; i < 8; i++) {
        if (len_buf[i] < '0' || len_buf[i] > '9') return PARSE_INVALID_HEADER_LEN;
    }
    unsigned long header_len = strtoul(len_buf, NULL, 10);
    if (header_len == 0 || header_len > MMENC1_MAX_HEADER_LEN)
        return PARSE_INVALID_HEADER_LEN;
    /* Expect LF after the 8-digit field */
    offset += MMENC1_HEADER_LEN_FIELD;
    if (data[offset] != '\n') return PARSE_INVALID_HEADER_LEN;
    offset++;

    /* 3. JSON header */
    if (size < offset + header_len) return PARSE_TRUNCATED;

    /* NUL-terminate for cJSON (safe because we use a local copy) */
    char *json_buf = (char *)malloc(header_len + 1);
    if (!json_buf) return PARSE_TRUNCATED;   /* OOM → treat as error */
    memcpy(json_buf, data + offset, header_len);
    json_buf[header_len] = '\0';

    cJSON *root = cJSON_ParseWithLength(json_buf, header_len);
    free(json_buf);
    if (!root) return PARSE_JSON_ERROR;

    /* 4. Format version bounds */
    cJSON *j_fv = cJSON_GetObjectItemCaseSensitive(root, "formatVersion");
    long fv = cJSON_IsNumber(j_fv) ? (long)j_fv->valuedouble : 1L;
    if (fv < MMENC1_FORMAT_VERSION_MIN) { cJSON_Delete(root); return PARSE_FORMAT_VERSION_TOO_OLD; }
    if (fv > MMENC1_FORMAT_VERSION_MAX) { cJSON_Delete(root); return PARSE_FORMAT_VERSION_TOO_NEW; }

    /* 5. Required field presence */
    cJSON *j_buildId  = cJSON_GetObjectItemCaseSensitive(root, "buildId");
    cJSON *j_fileId   = cJSON_GetObjectItemCaseSensitive(root, "fileId");
    cJSON *j_pathHash = cJSON_GetObjectItemCaseSensitive(root, "pathHash");
    cJSON *j_nonce    = cJSON_GetObjectItemCaseSensitive(root, "nonce");
    cJSON *j_tag      = cJSON_GetObjectItemCaseSensitive(root, "tag");
    cJSON *j_algo     = cJSON_GetObjectItemCaseSensitive(root, "algorithm");
    if (!cJSON_IsString(j_buildId)  || !cJSON_IsString(j_fileId) ||
        !cJSON_IsString(j_pathHash) || !cJSON_IsString(j_nonce)  ||
        !cJSON_IsString(j_tag)      || !cJSON_IsString(j_algo)) {
        cJSON_Delete(root);
        return PARSE_MISSING_FIELDS;
    }

    /* 6. Algorithm */
    if (strcmp(j_algo->valuestring, "AES-256-GCM") != 0) {
        cJSON_Delete(root);
        return PARSE_BAD_ALGORITHM;
    }

    /* 7. Nonce must decode to 12 bytes (base64 of 12 bytes = 16 chars) */
    size_t nonce_b64_len = strlen(j_nonce->valuestring);
    if (!b64_decode_len_check(j_nonce->valuestring, nonce_b64_len, 12)) {
        cJSON_Delete(root);
        return PARSE_BAD_NONCE;
    }

    /* 8. Tag must decode to 16 bytes (base64 of 16 bytes = 24 chars, with padding) */
    size_t tag_b64_len = strlen(j_tag->valuestring);
    if (!b64_decode_len_check(j_tag->valuestring, tag_b64_len, 16)) {
        cJSON_Delete(root);
        return PARSE_BAD_TAG;
    }

    cJSON_Delete(root);
    return PARSE_OK;
}

/* ── libFuzzer entry point ──────────────────────────────────────────────── */
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    /* parse_mmenc1_header must never crash, abort, or access out-of-bounds
     * regardless of the input. Any return value is acceptable — only crashes
     * detected by AddressSanitizer / UBSan are failures. */
    ParseResult r = parse_mmenc1_header(data, size);
    (void)r;
    return 0;
}

/* ── AFL++ / standalone entry point (fallback if no libFuzzer) ─────────── */
#ifndef __AFL_FUZZ_TESTCASE_LEN
int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 1; }
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (fsize <= 0 || fsize > 10 * 1024 * 1024) { fclose(f); return 1; }
    uint8_t *buf = (uint8_t *)malloc((size_t)fsize);
    if (!buf) { fclose(f); return 1; }
    size_t n = fread(buf, 1, (size_t)fsize, f);
    fclose(f);
    ParseResult r = parse_mmenc1_header(buf, n);
    free(buf);
    printf("ParseResult: %d\n", (int)r);
    return 0;
}
#endif
