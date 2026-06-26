PHP_ARG_ENABLE(mmloader, whether to enable MMProtect Loader,
[  --enable-mmloader        Enable MMProtect PHP loader])

if test "$PHP_MMLOADER" != "no"; then
  PHP_NEW_EXTENSION(mmloader, mmloader.c, $ext_shared)
  PHP_ADD_LIBRARY(crypto, 1, MMLOADER_SHARED_LIBADD)
  PHP_SUBST(MMLOADER_SHARED_LIBADD)
fi
