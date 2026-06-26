#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "php.h"
#include "php_ini.h"
#include "ext/standard/info.h"
#include "Zend/zend_compile.h"
#include "php_mmloader.h"

static zend_compile_file_t mmloader_original_compile_file = NULL;

ZEND_BEGIN_MODULE_GLOBALS(mmloader)
    zend_bool enabled;
    char *license_server;
    char *manifest_file;
    char *license_file;
    char *cache_dir;
    char *protected_magic;
    zend_long connect_timeout_ms;
    zend_long request_timeout_ms;
    zend_long lease_refresh_seconds;
    zend_long offline_grace_seconds;
    zend_bool require_signature;
ZEND_END_MODULE_GLOBALS(mmloader)

ZEND_DECLARE_MODULE_GLOBALS(mmloader)

#define MMLOADER_G(v) ZEND_MODULE_GLOBALS_ACCESSOR(mmloader, v)

PHP_INI_BEGIN()
    STD_PHP_INI_BOOLEAN("mmloader.enabled", "1", PHP_INI_SYSTEM, OnUpdateBool, enabled, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.license_server", "", PHP_INI_SYSTEM, OnUpdateString, license_server, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.manifest_file", ".mmprotect/manifest.json", PHP_INI_SYSTEM, OnUpdateString, manifest_file, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.license_file", ".mmprotect/license.json", PHP_INI_SYSTEM, OnUpdateString, license_file, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.cache_dir", "/var/cache/mmloader", PHP_INI_SYSTEM, OnUpdateString, cache_dir, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.protected_magic", "MMENC1", PHP_INI_SYSTEM, OnUpdateString, protected_magic, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.connect_timeout_ms", "3000", PHP_INI_SYSTEM, OnUpdateLong, connect_timeout_ms, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.request_timeout_ms", "5000", PHP_INI_SYSTEM, OnUpdateLong, request_timeout_ms, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.lease_refresh_seconds", "3600", PHP_INI_SYSTEM, OnUpdateLong, lease_refresh_seconds, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_ENTRY("mmloader.offline_grace_seconds", "604800", PHP_INI_SYSTEM, OnUpdateLong, offline_grace_seconds, zend_mmloader_globals, mmloader_globals)
    STD_PHP_INI_BOOLEAN("mmloader.require_signature", "1", PHP_INI_SYSTEM, OnUpdateBool, require_signature, zend_mmloader_globals, mmloader_globals)
PHP_INI_END()

static void php_mmloader_init_globals(zend_mmloader_globals *g)
{
    g->enabled = 1;
    g->license_server = NULL;
    g->manifest_file = NULL;
    g->license_file = NULL;
    g->cache_dir = NULL;
    g->protected_magic = NULL;
    g->connect_timeout_ms = 3000;
    g->request_timeout_ms = 5000;
    g->lease_refresh_seconds = 3600;
    g->offline_grace_seconds = 604800;
    g->require_signature = 1;
}

static int mmloader_file_starts_with_magic(zend_file_handle *file_handle)
{
    FILE *fp;
    char buffer[8] = {0};
    const char *filename;

    if (!file_handle || !file_handle->filename) {
        return 0;
    }

    filename = ZSTR_VAL(file_handle->filename);
    fp = fopen(filename, "rb");
    if (!fp) {
        return 0;
    }

    if (fread(buffer, 1, 6, fp) != 6) {
        fclose(fp);
        return 0;
    }

    fclose(fp);
    return memcmp(buffer, "MMENC1", 6) == 0;
}

static zend_string *mmloader_read_plain_demo(zend_file_handle *file_handle)
{
    /*
     * Produktive TODOs:
     * - MMENC1-Container lesen
     * - Header + Manifest parsen
     * - Header-/Manifest-Signaturen prüfen
     * - Runtime-Lease über HTTPS holen oder gecachte Lease prüfen
     * - File-Key per HKDF ableiten
     * - AES-256-GCM entschlüsseln
     * - Klartext als zend_string zurückgeben
     */
    (void)file_handle;
    return NULL;
}

static zend_op_array *mmloader_compile_file(zend_file_handle *file_handle, int type)
{
    zend_string *plain;
    zend_op_array *op_array;

    if (!MMLOADER_G(enabled)) {
        return mmloader_original_compile_file(file_handle, type);
    }

    if (!mmloader_file_starts_with_magic(file_handle)) {
        return mmloader_original_compile_file(file_handle, type);
    }

    plain = mmloader_read_plain_demo(file_handle);
    if (!plain) {
        zend_error(E_COMPILE_ERROR,
            "MMENC: protected PHP file detected, but runtime decoder is not implemented yet");
        return NULL;
    }

    op_array = zend_compile_string(plain, ZSTR_VAL(file_handle->filename), ZEND_COMPILE_POSITION_AFTER_OPEN_TAG);

    /*
     * TODO:
     * - op_array als geschützt markieren
     * - execute_ex hook hinzufügen
     * - Runtime-Lease in RINIT prüfen
     * - Klartext-Puffer sicher nullen
     */

    zend_string_release(plain);
    return op_array;
}

PHP_MINIT_FUNCTION(mmloader)
{
    ZEND_INIT_MODULE_GLOBALS(mmloader, php_mmloader_init_globals, NULL);
    REGISTER_INI_ENTRIES();

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
    return SUCCESS;
}

PHP_RINIT_FUNCTION(mmloader)
{
#if defined(ZTS) && defined(COMPILE_DL_MMLOADER)
    ZEND_TSRMLS_CACHE_UPDATE();
#endif
    return SUCCESS;
}

PHP_MINFO_FUNCTION(mmloader)
{
    php_info_print_table_start();
    php_info_print_table_header(2, "MMProtect Loader", "enabled");
    php_info_print_table_row(2, "Version", PHP_MMLOADER_VERSION);
    php_info_print_table_row(2, "Magic", MMLOADER_G(protected_magic) ? MMLOADER_G(protected_magic) : "MMENC1");
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
