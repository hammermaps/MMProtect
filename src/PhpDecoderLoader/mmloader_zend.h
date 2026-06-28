/* mmloader_zend.h — Abstraction layer over Zend Engine internals.
 *
 * All direct accesses to Zend Engine struct members and API symbols that
 * could vary between PHP 8.x/9.x live here as static inline wrappers.
 * mmloader.c uses only these wrappers; no Zend internals appear there
 * directly.
 *
 * Design constraints:
 *   - Header-only (static inline) → zero runtime overhead.
 *   - No references to mmloader globals (MMLOADER_G); callers pass state
 *     explicitly so the wrappers stay reusable.
 *   - Function signatures mirror the abstracted concept, not the Zend API.
 */
#ifndef MMLOADER_ZEND_H
#define MMLOADER_ZEND_H

#include "php.h"
#include "Zend/zend_compile.h"

/* ======================================================================
 * § 1  Function-pointer types for the two hookaable engine globals
 * ====================================================================== */

typedef zend_op_array *(*mm_compile_file_fn)(zend_file_handle *, int);
typedef void           (*mm_execute_fn)(zend_execute_data *);

/* ======================================================================
 * § 2  Hook management
 *
 * Install a replacement for zend_compile_file / zend_execute_ex and
 * return the pointer that was there before (to be stored by the caller
 * and passed back to mm_unhook_* on shutdown).
 * ====================================================================== */

static inline mm_compile_file_fn mm_hook_compile_file(mm_compile_file_fn new_fn)
{
    mm_compile_file_fn orig = (mm_compile_file_fn)zend_compile_file;
    zend_compile_file = new_fn;
    return orig;
}

static inline void mm_unhook_compile_file(mm_compile_file_fn orig)
{
    if (orig) zend_compile_file = orig;
}

static inline mm_execute_fn mm_hook_execute_ex(mm_execute_fn new_fn)
{
    mm_execute_fn orig = zend_execute_ex;
    zend_execute_ex = new_fn;
    return orig;
}

static inline void mm_unhook_execute_ex(mm_execute_fn orig)
{
    if (orig) zend_execute_ex = orig;
}

/* ======================================================================
 * § 3  File-handle inspection
 * ====================================================================== */

/* Return the filesystem path stored in a compile-time file handle,
 * or NULL if the handle carries no filename. */
static inline const char *mm_file_handle_path(zend_file_handle *fh)
{
    return fh->filename ? ZSTR_VAL(fh->filename) : NULL;
}

/* ======================================================================
 * § 4  Execute-data inspection
 * ====================================================================== */

/* Return the source-file path of the function being executed,
 * or NULL when the frame is not a PHP user-defined function. */
static inline const char *mm_execute_data_source_path(zend_execute_data *ed)
{
    if (!ed || !ed->func) return NULL;
    zend_function *fn = ed->func;
    if (fn->type != ZEND_USER_FUNCTION) return NULL;
    if (!fn->op_array.filename) return NULL;
    return ZSTR_VAL(fn->op_array.filename);
}

/* ======================================================================
 * § 5  Compile string
 *
 * Feed a decrypted PHP source string into the compiler.  The original
 * file path is passed as the filename so __FILE__ and error messages
 * remain correct.
 * ====================================================================== */

static inline zend_op_array *mm_compile_plaintext(zend_string *source,
                                                   const char  *filename)
{
    return zend_compile_string(source, (char *)filename,
                               ZEND_COMPILE_POSITION_AT_OPEN_TAG);
}

/* ======================================================================
 * § 6  Zend-string helpers
 * ====================================================================== */

/* Allocate a non-persistent zend_string from a raw byte buffer. */
static inline zend_string *mm_zstr_new(const char *data, size_t len)
{
    return zend_string_init(data, len, 0);
}

/* Overwrite the buffer with zeros, then release the zend_string.
 * Use whenever the string contains key material or plaintext PHP. */
static inline void mm_zstr_secure_release(zend_string *s)
{
    if (!s) return;
    ZEND_SECURE_ZERO(ZSTR_VAL(s), ZSTR_LEN(s));
    zend_string_release(s);
}

/* Typed access to the string payload — avoids bare ZSTR_VAL/ZSTR_LEN
 * at call sites outside this header. */
#define mm_zstr_val(s)  ZSTR_VAL(s)
#define mm_zstr_len(s)  ZSTR_LEN(s)

/* ======================================================================
 * § 7  Protected-files set
 *
 * A persistent HashTable that tracks which MMENC1 source files have been
 * decrypted by this loader process.  Used by the execute_ex OPcache guard.
 * ====================================================================== */

static inline void mm_protected_init(HashTable **ht)
{
    *ht = pemalloc(sizeof(HashTable), 1);
    zend_hash_init(*ht, 64, NULL, NULL, 1);
}

static inline void mm_protected_destroy(HashTable **ht)
{
    if (!*ht) return;
    zend_hash_destroy(*ht);
    pefree(*ht, 1);
    *ht = NULL;
}

static inline void mm_protected_mark(HashTable *ht, const char *filename)
{
    if (!ht || !filename) return;
    zend_hash_str_add_empty_element(ht, filename, strlen(filename));
}

static inline int mm_protected_check(HashTable *ht, const char *filename)
{
    if (!ht || !filename) return 0;
    return zend_hash_str_exists(ht, filename, strlen(filename));
}

/* ======================================================================
 * § 8  Magic-file cache
 *
 * A persistent HashTable that maps filename → 1 (MMENC1) or 0 (plain PHP).
 * Avoids repeated file-I/O in the hot execute_ex path.
 * ====================================================================== */

static inline void mm_magic_cache_init(HashTable **ht)
{
    *ht = pemalloc(sizeof(HashTable), 1);
    zend_hash_init(*ht, 64, NULL, ZVAL_PTR_DTOR, 1);
}

static inline void mm_magic_cache_destroy(HashTable **ht)
{
    if (!*ht) return;
    zend_hash_destroy(*ht);
    pefree(*ht, 1);
    *ht = NULL;
}

/* Returns 1 = is MMENC1, 0 = plain PHP, -1 = not yet cached. */
static inline int mm_magic_cache_lookup(HashTable *ht,
                                         const char *filename, size_t fname_len)
{
    if (!ht) return -1;
    zval *v = zend_hash_str_find(ht, filename, fname_len);
    if (!v) return -1;
    return Z_LVAL_P(v) == 1 ? 1 : 0;
}

static inline void mm_magic_cache_store(HashTable *ht,
                                         const char *filename, size_t fname_len,
                                         int is_mmenc1)
{
    if (!ht) return;
    zval v;
    ZVAL_LONG(&v, is_mmenc1);
    zend_hash_str_add(ht, filename, fname_len, &v);
}

/* ======================================================================
 * § 9  Feature set
 *
 * A persistent HashTable of feature-name strings granted by the last
 * successful runtime lease.  Backs mmprotect_has_feature() and is
 * serialised to / deserialised from the disk lease cache.
 * ====================================================================== */

static inline void mm_features_destroy(HashTable **ht)
{
    if (!*ht) return;
    zend_hash_destroy(*ht);
    pefree(*ht, 1);
    *ht = NULL;
}

/* (Re-)create an empty feature set with the given initial capacity. */
static inline void mm_features_reset(HashTable **ht, uint32_t capacity)
{
    mm_features_destroy(ht);
    *ht = pemalloc(sizeof(HashTable), 1);
    zend_hash_init(*ht, capacity, NULL, NULL, 1);
}

static inline void mm_features_add(HashTable *ht, const char *name)
{
    if (!ht || !name) return;
    zend_hash_str_add_empty_element(ht, name, strlen(name));
}

/* Returns 1 when the feature is present, 0 otherwise. */
static inline int mm_features_has(HashTable *ht, const char *name, size_t len)
{
    if (!ht || len == 0) return 0;
    return zend_hash_str_exists(ht, name, len);
}

/* Iterate feature names; cb is called with each name as a NUL-terminated
 * C string.  Keeps ZEND_HASH_FOREACH_* inside this header. */
typedef void (*mm_feature_cb)(const char *name, void *userdata);

static inline void mm_features_each(HashTable *ht, mm_feature_cb cb, void *userdata)
{
    if (!ht) return;
    zend_string *key;
    ZEND_HASH_FOREACH_STR_KEY(ht, key) {
        if (key) cb(ZSTR_VAL(key), userdata);
    } ZEND_HASH_FOREACH_END();
}

#endif /* MMLOADER_ZEND_H */
