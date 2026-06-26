#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "php.h"
#include "php_ini.h"
#include "ext/standard/info.h"
#include "Zend/zend_compile.h"
#include "php_mmloader.h"

#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/params.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

#include "vendor/cjson/cJSON.h"

/* ====================================================================
 * Module globals
 * ==================================================================== */

typedef zend_op_array *(*mmloader_compile_file_t)(zend_file_handle *, int);
static mmloader_compile_file_t mmloader_original_compile_file = NULL;

ZEND_BEGIN_MODULE_GLOBALS(mmloader)
    zend_bool  enabled;
    char      *license_server;
    char      *manifest_file;
    char      *license_file;
    char      *cache_dir;
    char      *protected_magic;
    char      *dev_buildkey;          /* path to Base64-encoded 32-byte build key (Week 1) */
    zend_long  connect_timeout_ms;
    zend_long  request_timeout_ms;
    zend_long  lease_refresh_seconds;
    zend_long  offline_grace_seconds;
    zend_bool  require_signature;
    zend_bool  dev_mode;              /* Week 2: skip TLS verification */
    /* Week 2+ per-process lease cache (populated by HTTP lease call) */
    char      *cached_build_id;
    time_t     cached_lease_expires;
ZEND_END_MODULE_GLOBALS(mmloader)

ZEND_DECLARE_MODULE_GLOBALS(mmloader)

#define MMLOADER_G(v) ZEND_MODULE_GLOBALS_ACCESSOR(mmloader, v)

/* Pre-computed HKDF salt = SHA-256("MMProtect-HKDF-v1") */
static unsigned char s_hkdf_salt[32];

/* ====================================================================
 * INI entries
 * ==================================================================== */

PHP_INI_BEGIN()
    STD_PHP_INI_BOOLEAN("mmloader.enabled", "1", PHP_INI_SYSTEM,
        OnUpdateBool, enabled, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.license_server", "", PHP_INI_SYSTEM,
        OnUpdateString, license_server, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.manifest_file", ".mmprotect/manifest.json", PHP_INI_SYSTEM,
        OnUpdateString, manifest_file, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.license_file", ".mmprotect/license.json", PHP_INI_SYSTEM,
        OnUpdateString, license_file, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.cache_dir", "/var/cache/mmloader", PHP_INI_SYSTEM,
        OnUpdateString, cache_dir, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.protected_magic", "MMENC1", PHP_INI_SYSTEM,
        OnUpdateString, protected_magic, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.dev_buildkey", "", PHP_INI_SYSTEM,
        OnUpdateString, dev_buildkey, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.connect_timeout_ms", "3000", PHP_INI_SYSTEM,
        OnUpdateLong, connect_timeout_ms, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.request_timeout_ms", "5000", PHP_INI_SYSTEM,
        OnUpdateLong, request_timeout_ms, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.lease_refresh_seconds", "3600", PHP_INI_SYSTEM,
        OnUpdateLong, lease_refresh_seconds, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.offline_grace_seconds", "604800", PHP_INI_SYSTEM,
        OnUpdateLong, offline_grace_seconds, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_BOOLEAN("mmloader.require_signature", "1", PHP_INI_SYSTEM,
        OnUpdateBool, require_signature, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_BOOLEAN("mmloader.dev_mode", "0", PHP_INI_SYSTEM,
        OnUpdateBool, dev_mode, zend_mmloader_globals, mmloader_globals)
PHP_INI_END()

static void php_mmloader_init_globals(zend_mmloader_globals *g)
{
    g->enabled              = 1;
    g->license_server       = NULL;
    g->manifest_file        = NULL;
    g->license_file         = NULL;
    g->cache_dir            = NULL;
    g->protected_magic      = NULL;
    g->dev_buildkey         = NULL;
    g->connect_timeout_ms   = 3000;
    g->request_timeout_ms   = 5000;
    g->lease_refresh_seconds  = 3600;
    g->offline_grace_seconds  = 604800;
    g->require_signature    = 1;
    g->dev_mode             = 0;
    g->cached_build_id      = NULL;
    g->cached_lease_expires = 0;
}

/* ====================================================================
 * Crypto helpers
 * ==================================================================== */

/*
 * Decode standard Base64 (no newlines) into output.
 * Returns 1 on success, 0 on failure.
 */
static int mmloader_base64_decode(const char *input, size_t input_len,
                                   unsigned char *output, size_t *output_len)
{
    BIO *b64 = BIO_new(BIO_f_base64());
    if (!b64) return 0;

    BIO *mem = BIO_new_mem_buf(input, (int)input_len);
    if (!mem) { BIO_free(b64); return 0; }

    BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
    BIO_push(b64, mem);  /* b64 is the head; mem is freed with it */

    int n = BIO_read(b64, output, (int)input_len);
    BIO_free_all(b64);

    if (n <= 0) return 0;
    *output_len = (size_t)n;
    return 1;
}

/*
 * HKDF-SHA256.
 * IKM = ikm[0..ikm_len], salt = s_hkdf_salt (pre-computed), info = info[0..info_len].
 * Output written to out[0..out_len].
 * Returns 1 on success, 0 on failure.
 */
static int mmloader_hkdf(const unsigned char *ikm, size_t ikm_len,
                          const char *info,         size_t info_len,
                          unsigned char *out,        size_t out_len)
{
    int ok = 0;
    EVP_KDF     *kdf  = EVP_KDF_fetch(NULL, "HKDF", NULL);
    if (!kdf) return 0;
    EVP_KDF_CTX *kctx = EVP_KDF_CTX_new(kdf);
    EVP_KDF_free(kdf);
    if (!kctx) return 0;

    char digest[] = "SHA-256";
    OSSL_PARAM params[] = {
        OSSL_PARAM_construct_utf8_string("digest",  digest, 0),
        OSSL_PARAM_construct_octet_string("key",    (void *)ikm,        ikm_len),
        OSSL_PARAM_construct_octet_string("salt",   (void *)s_hkdf_salt, sizeof(s_hkdf_salt)),
        OSSL_PARAM_construct_octet_string("info",   (void *)info,       info_len),
        OSSL_PARAM_END
    };

    if (EVP_KDF_derive(kctx, out, out_len, params) > 0) ok = 1;
    EVP_KDF_CTX_free(kctx);
    return ok;
}

/*
 * AES-256-GCM decryption (OpenSSL EVP_CIPHER_CTX, standard OpenSSL 1.1.x/3.x).
 * plaintext must have at least ct_len bytes allocated.
 * Returns 1 on success (authentication tag matched), 0 on failure.
 */
static int mmloader_aes256gcm_decrypt(
    const unsigned char *key,
    const unsigned char *nonce,      size_t nonce_len,
    const unsigned char *ciphertext, size_t ct_len,
    const unsigned char *tag,        size_t tag_len,
    unsigned char       *plaintext,  size_t *pt_len)
{
    int ok = 0, len = 0, final_len = 0;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return 0;

    if (!EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL))      goto done;
    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, (int)nonce_len, NULL)) goto done;
    if (!EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce))                   goto done;
    if (!EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, (int)ct_len))  goto done;
    /* Set the expected tag before calling DecryptFinal */
    if (!EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, (int)tag_len, (void *)tag)) goto done;
    if (EVP_DecryptFinal_ex(ctx, plaintext + len, &final_len) <= 0)         goto done;

    *pt_len = (size_t)(len + final_len);
    ok = 1;

done:
    EVP_CIPHER_CTX_free(ctx);
    return ok;
}

/*
 * Read the dev build key from the INI-configured path and Base64-decode it.
 * Writes exactly 32 bytes into key_out on success.
 * Returns 1 on success, 0 on failure.
 */
static int mmloader_read_dev_buildkey(unsigned char *key_out)
{
    const char *path = MMLOADER_G(dev_buildkey);
    if (!path || path[0] == '\0') {
        php_error_docref(NULL, E_WARNING,
            "MMENC: mmloader.dev_buildkey not configured");
        return 0;
    }

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: cannot open dev_buildkey: %s", path);
        return 0;
    }

    char b64[256] = {0};
    size_t n = fread(b64, 1, sizeof(b64) - 1, fp);
    fclose(fp);

    /* strip trailing whitespace / newlines */
    while (n > 0 && (b64[n-1] == '\n' || b64[n-1] == '\r' ||
                     b64[n-1] == ' '  || b64[n-1] == '\t'))
        b64[--n] = '\0';

    size_t key_len = 0;
    if (!mmloader_base64_decode(b64, n, key_out, &key_len) || key_len != 32) {
        memset(b64, 0, sizeof(b64));
        php_error_docref(NULL, E_WARNING,
            "MMENC: dev_buildkey must be Base64 of exactly 32 bytes (got %zu)", key_len);
        return 0;
    }
    memset(b64, 0, sizeof(b64));
    return 1;
}

/* ====================================================================
 * MMENC1 parser + decrypt pipeline
 * ==================================================================== */

/*
 * Decrypt an MMENC1 file whose FILE* is already open and positioned at
 * offset 7 (after "MMENC1\n").  The function takes ownership of fp and
 * always closes it before returning.
 *
 * Week 1: build key is read from mmloader.dev_buildkey file.
 * Week 2: build key will come from the HTTP lease response (runtimeKey).
 *
 * Returns a new non-persistent zend_string containing the plaintext PHP
 * source on success, NULL on failure.
 */
static zend_string *mmloader_decrypt_from_fp(FILE *fp, const char *filename)
{
    zend_string  *result     = NULL;
    char         *header_json = NULL;
    unsigned char *ciphertext = NULL;
    unsigned char *plaintext  = NULL;
    cJSON        *root        = NULL;
    char         *info        = NULL;

    /* --- Read 8-byte ASCII header length + LF (9 bytes total) --- */
    char len_buf[9];
    if (fread(len_buf, 1, 9, fp) != 9 || len_buf[8] != '\n') {
        php_error_docref(NULL, E_WARNING,
            "MMENC: malformed header length in %s", filename);
        goto cleanup;
    }
    len_buf[8] = '\0';
    size_t header_len = (size_t)strtoul(len_buf, NULL, 10);
    if (header_len == 0 || header_len > 65536) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: header length out of range (%zu) in %s", header_len, filename);
        goto cleanup;
    }

    /* --- Read JSON header --- */
    header_json = emalloc(header_len + 1);
    if (fread(header_json, 1, header_len, fp) != header_len) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: truncated JSON header in %s", filename);
        goto cleanup;
    }
    header_json[header_len] = '\0';

    /* --- Determine ciphertext offset and length via file size --- */
    /* Current offset: 7 (magic+LF) + 9 (len+LF) + header_len = 16 + header_len */
    long ct_start = 16L + (long)header_len;
    if (fseek(fp, 0, SEEK_END) != 0) goto cleanup;
    long file_size = ftell(fp);
    if (file_size < 0 || file_size <= ct_start) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: no ciphertext in %s", filename);
        goto cleanup;
    }
    fseek(fp, ct_start, SEEK_SET);
    size_t ct_len = (size_t)(file_size - ct_start);
    if (ct_len > 256 * 1024 * 1024) {  /* 256 MB sanity cap */
        php_error_docref(NULL, E_WARNING,
            "MMENC: ciphertext too large in %s", filename);
        goto cleanup;
    }

    /* --- Read ciphertext --- */
    ciphertext = emalloc(ct_len);
    if (fread(ciphertext, 1, ct_len, fp) != ct_len) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: truncated ciphertext in %s", filename);
        goto cleanup;
    }
    fclose(fp); fp = NULL;  /* done with file */

    /* --- Parse JSON header --- */
    root = cJSON_ParseWithLength(header_json, header_len);
    if (!root) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: JSON header parse error in %s", filename);
        goto cleanup;
    }

    cJSON *j_buildId  = cJSON_GetObjectItemCaseSensitive(root, "buildId");
    cJSON *j_fileId   = cJSON_GetObjectItemCaseSensitive(root, "fileId");
    cJSON *j_pathHash = cJSON_GetObjectItemCaseSensitive(root, "pathHash");
    cJSON *j_nonce    = cJSON_GetObjectItemCaseSensitive(root, "nonce");
    cJSON *j_tag      = cJSON_GetObjectItemCaseSensitive(root, "tag");
    cJSON *j_algo     = cJSON_GetObjectItemCaseSensitive(root, "algorithm");

    if (!cJSON_IsString(j_buildId)  || !cJSON_IsString(j_fileId) ||
        !cJSON_IsString(j_pathHash) || !cJSON_IsString(j_nonce)  ||
        !cJSON_IsString(j_tag)      || !cJSON_IsString(j_algo)) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: missing required header fields in %s", filename);
        goto cleanup;
    }

    if (strcmp(j_algo->valuestring, "AES-256-GCM") != 0) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: unsupported algorithm '%s' in %s",
            j_algo->valuestring, filename);
        goto cleanup;
    }

    /* --- Base64-decode nonce (12 bytes) and tag (16 bytes) --- */
    unsigned char nonce[12], tag[16];
    size_t nonce_len = 0, tag_len = 0;

    if (!mmloader_base64_decode(j_nonce->valuestring,
                                strlen(j_nonce->valuestring),
                                nonce, &nonce_len) || nonce_len != 12) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: nonce decode failed in %s", filename);
        goto cleanup;
    }
    if (!mmloader_base64_decode(j_tag->valuestring,
                                strlen(j_tag->valuestring),
                                tag, &tag_len) || tag_len != 16) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: tag decode failed in %s", filename);
        goto cleanup;
    }

    /* --- Build HKDF info string: "buildId:fileId:pathHash"
     * pathHash is taken verbatim from the header field — it already contains
     * the "sha256:" prefix (e.g. "sha256:deadbeef..."), matching the encoder. --- */
    size_t info_len = strlen(j_buildId->valuestring) + 1 +
                      strlen(j_fileId->valuestring)  + 1 +
                      strlen(j_pathHash->valuestring);
    info = emalloc(info_len + 1);
    snprintf(info, info_len + 1, "%s:%s:%s",
             j_buildId->valuestring,
             j_fileId->valuestring,
             j_pathHash->valuestring);

    /* --- Get build key ---
     * Week 1: read from dev_buildkey INI file.
     * Week 2: replace with runtimeKey from HTTP lease response. --- */
    unsigned char build_key[32];
    if (!mmloader_read_dev_buildkey(build_key)) goto cleanup;

    /* --- Derive per-file AES key via HKDF-SHA256 --- */
    unsigned char file_key[32];
    int hkdf_ok = mmloader_hkdf(build_key, 32, info, info_len, file_key, 32);
    ZEND_SECURE_ZERO(build_key, sizeof(build_key));
    ZEND_SECURE_ZERO(info, info_len);
    efree(info); info = NULL;
    if (!hkdf_ok) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: HKDF derivation failed for %s", filename);
        goto cleanup;
    }

    /* --- AES-256-GCM decrypt --- */
    plaintext = emalloc(ct_len);   /* AES-GCM plaintext is same length as ciphertext */
    size_t pt_len = 0;

    int dec_ok = mmloader_aes256gcm_decrypt(
        file_key, nonce, 12, ciphertext, ct_len, tag, 16, plaintext, &pt_len);

    ZEND_SECURE_ZERO(file_key, sizeof(file_key));
    ZEND_SECURE_ZERO(nonce,    sizeof(nonce));
    ZEND_SECURE_ZERO(tag,      sizeof(tag));

    /* D13: zero ciphertext immediately after decrypt — it's no longer needed */
    ZEND_SECURE_ZERO(ciphertext, ct_len);
    efree(ciphertext); ciphertext = NULL;

    if (!dec_ok) {
        php_error_docref(NULL, E_WARNING,
            "MMENC: AES-GCM authentication failed for %s "
            "(wrong build key or corrupted file)", filename);
        /* plaintext may hold garbage — zero before cleanup */
        if (plaintext) ZEND_SECURE_ZERO(plaintext, ct_len);
        goto cleanup;
    }

    /* --- Hand plaintext to Zend ---
     * zend_string_init makes an internal copy of plaintext. --- */
    result = zend_string_init((const char *)plaintext, pt_len, 0);

    /* D13: zero the raw AES output buffer before freeing */
    ZEND_SECURE_ZERO(plaintext, ct_len);
    efree(plaintext); plaintext = NULL;

cleanup:
    if (fp)          { fclose(fp); }
    if (info)        { efree(info); }
    if (header_json) { efree(header_json); }
    if (ciphertext)  { ZEND_SECURE_ZERO(ciphertext, ct_len); efree(ciphertext); }
    if (plaintext)   { ZEND_SECURE_ZERO(plaintext,  ct_len); efree(plaintext); }
    if (root)        { cJSON_Delete(root); }
    return result;
}

/* ====================================================================
 * Compile hook
 * ==================================================================== */

static zend_op_array *mmloader_compile_file(zend_file_handle *file_handle, int type)
{
    if (!MMLOADER_G(enabled)) {
        return mmloader_original_compile_file(file_handle, type);
    }

    const char *filename = ZSTR_VAL(file_handle->filename);

    /* TOCTOU fix (D4): open the file once and keep it open through the full
     * decrypt pipeline, so the file cannot be swapped between the magic check
     * and the actual read. */
    FILE *fp = fopen(filename, "rb");
    if (!fp) {
        return mmloader_original_compile_file(file_handle, type);
    }

    char magic[7];
    if (fread(magic, 1, 7, fp) != 7 || memcmp(magic, "MMENC1\n", 7) != 0) {
        fclose(fp);
        return mmloader_original_compile_file(file_handle, type);
    }
    /* fp is now positioned at offset 7; mmloader_decrypt_from_fp takes ownership */

    zend_string *plain = mmloader_decrypt_from_fp(fp, filename);
    /* fp is closed inside mmloader_decrypt_from_fp regardless of outcome */

    if (!plain) {
        zend_error(E_COMPILE_ERROR,
            "MMENC: failed to decrypt protected file: %s", filename);
        return NULL;
    }

    /* D12: AT_OPEN_TAG — encoder encrypts the full file including <?php tag.
     * AFTER_OPEN_TAG would treat "<?php" as literal text output. */
    zend_op_array *op_array = zend_compile_string(
        plain, (char *)filename, ZEND_COMPILE_POSITION_AT_OPEN_TAG);

    /* D13: zero the zend_string's value before releasing it.
     * Note: Zend may have internalized string literals from the compiled
     * source — those copies cannot be zeroed (known limitation). */
    ZEND_SECURE_ZERO(ZSTR_VAL(plain), ZSTR_LEN(plain));
    zend_string_release(plain);

    return op_array;
}

/* ====================================================================
 * Extension lifecycle
 * ==================================================================== */

PHP_MINIT_FUNCTION(mmloader)
{
    ZEND_INIT_MODULE_GLOBALS(mmloader, php_mmloader_init_globals, NULL);
    REGISTER_INI_ENTRIES();

    /* Pre-compute HKDF salt = SHA-256("MMProtect-HKDF-v1").
     * Doing it once at module init avoids repeated hashing at compile time. */
    unsigned int salt_len = 0;
    if (!EVP_Digest("MMProtect-HKDF-v1", strlen("MMProtect-HKDF-v1"),
                    s_hkdf_salt, &salt_len, EVP_sha256(), NULL) || salt_len != 32) {
        php_error(E_CORE_ERROR, "MMENC: failed to initialise HKDF salt");
        return FAILURE;
    }

    mmloader_original_compile_file = zend_compile_file;
    zend_compile_file = mmloader_compile_file;
    return SUCCESS;
}

PHP_MSHUTDOWN_FUNCTION(mmloader)
{
    if (mmloader_original_compile_file) {
        zend_compile_file = mmloader_original_compile_file;
    }
    UNREGISTER_INI_ENTRIES();
    ZEND_SECURE_ZERO(s_hkdf_salt, sizeof(s_hkdf_salt));
    return SUCCESS;
}

PHP_RINIT_FUNCTION(mmloader)
{
#if defined(ZTS) && defined(COMPILE_DL_MMLOADER)
    ZEND_TSRMLS_CACHE_UPDATE();
#endif
    /* Week 2: proactive lease refresh will go here */
    return SUCCESS;
}

PHP_MINFO_FUNCTION(mmloader)
{
    php_info_print_table_start();
    php_info_print_table_header(2, "MMProtect Loader", "enabled");
    php_info_print_table_row(2, "Version", PHP_MMLOADER_VERSION);
    php_info_print_table_row(2, "Magic",
        MMLOADER_G(protected_magic) ? MMLOADER_G(protected_magic) : "MMENC1");
    php_info_print_table_row(2, "Dev mode",
        MMLOADER_G(dev_mode) ? "on (Week 1 — no HTTP lease)" : "off");
    php_info_print_table_end();
    DISPLAY_INI_ENTRIES();
}

zend_module_entry mmloader_module_entry = {
    STANDARD_MODULE_HEADER,
    "mmloader",
    NULL,
    PHP_MINIT(mmloader),
    PHP_MSHUTDOWN(mmloader),
    PHP_RINIT(mmloader),
    NULL,
    PHP_MINFO(mmloader),
    PHP_MMLOADER_VERSION,
    STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_MMLOADER
# ifdef ZTS
ZEND_TSRMLS_CACHE_DEFINE()
# endif
ZEND_GET_MODULE(mmloader)
#endif
