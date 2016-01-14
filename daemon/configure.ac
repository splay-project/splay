#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
AC_INIT([splay-daemon], [1.0], [raziel.carvajal@unine.ch])
AM_INIT_AUTOMAKE
AM_CONFIG_HEADER(config.h)
CPPFLAGS='-I../../include'
AC_PROG_CC
if test x$prefix == xNONE ; then
  prefix=$HOME
fi
prefix=$prefix/$PACKAGE_NAME
AC_SUBST([prefix])
AC_CANONICAL_HOST
case $host_os in
  darwin*)
    cflags="-fno-common -dynamiclib -undefined dynamic_lookup"
    linker_flags="-ldl"
    llua="-llua"
    user_prof=".bash_profile"
    ;;
  linux*)
    cflags="-fpic"
    linker_flags=
    llua="-llua5.2"
    user_prof=".bashrc"
    ;;
  *)
    AC_MSG_ERROR([Your platform is not supported])
    ;;
esac
AC_SUBST([linker_flags])
AC_SUBST([llua])
AC_SUBST([cflags])
AC_SUBST([user_prof])

AC_CHECK_PROG([HAVE_LUA], [lua], [true], [false])
if test x$HAVE_LUA = xtrue ; then
  AC_MSG_CHECKING([Lua is installed])
else
  AC_MSG_CHECKING([Lua is not installed. Splay-deamon requires having the interpreter Lua\
  installed on your system, please, once you have finished with the compilation of\
  splay-daemon install Lua.])
fi

AC_CHECK_PROG([HAVE_OPENSSL], [openssl], [true], [false])
if test x$HAVE_OPENSSL = xtrue ; then
  AC_MSG_CHECKING([OpenSsl is installed])
else
  AC_MSG_ERROR([OpenSsl is not installed. Splay-deamon requires OpenSsl to be compiled, \
  please, install OpenSsl and do ./configure again.])
fi

AC_TYPE_SIZE_T
AC_FUNC_REALLOC
#TODO complete this macro (with the argument inlcudes at the 4th position) for
#having full portability in Darwin and Windows. Most of the work must be done
#for windows. NOTE: take into accoun Valerio's comment about the lack of
#compatibility in Windowns.
AC_CHECK_HEADERS(["arpa/inet.h" "fcntl.h" "netinet/in.h" "stdlib.h" "string.h" \
"sys/socket.h" "unistd.h"])

AC_ARG_ENABLE([lua-headers],
  AS_HELP_STRING([--enable-lua-headers=Dir], [Directory where Lua headers are located, by\
  default this argument is empty]),
  [LUA_HEADERS="${enableval}"; have_lua_headers=yes],
  [have_lua_headers=no]
)
AM_CONDITIONAL([lua_headers], [test "x$have_lua_headers" = "xyes"])
AC_SUBST([LUA_HEADERS])

AC_CHECK_HEADERS(["lua5.2/lua.h"], [
  AC_DEFINE(HAVE_LUA_52, 1, [liblua-dev in its version 5.2 was found])], [
#  AC_CHECK_HEADERS(["lua5.2/lua.h"], [
#    AC_DEFINE(HAVE_LUA_52, 1, [liblua-dev in its version 5.2 was found])], [
  if test x$have_lua_headers = xno ; then
    AC_MSG_CHECKING([Headers files of Lua were not found, you must do ./configure with the\
    flag --enable-lua-headers=/dir/to/lua/headers specifying the path where the headers of\
    Lua are located.])
  else
    AC_MSG_CHECKING([Directory of Lua headers was set by the user])
  fi
#  ])
])

AC_ARG_ENABLE([lua-library],
  AS_HELP_STRING([--enable-lua-library=Dir], [Directory where the Lua library is located, by\
  default this argument is empty]),
  [LUA_LIBRARY="${enableval}"; have_lua_lib=yes],
  [have_lua_lib=no]
)
AM_CONDITIONAL([lua_lib], [test "x$have_lua_lib" = "xyes"])
AC_SUBST([LUA_LIBRARY])

AC_SEARCH_LIBS(lua_close, [lua5.2], [], [
#  AC_MSG_CHECKING([liblua5.1 is not installed, looking for another version...])
#  AC_SEARCH_LIBS(lua_close, [lua5.2], [], [
  if test x$have_lua_lib = xno ; then
    AC_MSG_CHECKING([liblua5.2 is not install neither, you must do ./configure with the\
    flag --enable-lua-library=/dir/to/lua/library specifying the path where the files of\
    liblua (tipically, files with the extension .so) are located.])
  else
    AC_MSG_CHECKING([Lualib directory was set by the user])
  fi
#  ])
])

AC_SEARCH_LIBS(SSL_accept, [ssl], [], [
  AC_MSG_CHECKING([LibOpenssl is not installed, you must do ./configure with the flag\
  --enable-openssl-library=/dir/to/openssl/library specifying the path where the files of\
  LibOpenssl are located (tipically, files with the extension .so).])
])

AC_SEARCH_LIBS(DSA_new, [crypto], [], [
  AC_MSG_CHECKING([LibCrypto is not installed, you must do ./configure with the flag\
  --enable-crypto-library=/dir/to/crypto/library specifying the path where the files of\
  LibCrypto are located (tipically, files with the extension .so).])
])

AC_ARG_WITH([luabase64], AS_HELP_STRING([--with-luabase64], [Compile base64 library for Lua5.2]))
AS_IF([test "x$with_luabase64" = "xyes"], [have_luabase64=yes], [have_luabase64=no])
AM_CONDITIONAL([luabase64],[test "x$have_luabase64" = "xyes"])

AC_ARG_ENABLE([openssl-library],
  AS_HELP_STRING([--enable-openssl-library=Dir], [Directory where the OpenSsl library is located,\
  by default this argument is empty]),
  [OPENSSL_LIBRARY="${enableval}"; have_ssl_lib=yes],
  [have_ssl_lib=no]
)
AM_CONDITIONAL([ssl_lib], [test "x$have_ssl_lib" = "xyes"])
AC_SUBST([OPENSSL_LIBRARY])

AC_ARG_ENABLE([crypto-library],
  AS_HELP_STRING([--enable-crypto-library=Dir], [Directory where the Crypto library is located,\
  by default this argument is empty]),
  [CRYPTO_LIBRARY="${enableval}"; have_crypto_lib=yes],
  [have_crypto_lib=no]
)
AM_CONDITIONAL([crypto_lib], [test "x$have_crypto_lib" = "xyes"])
AC_SUBST([CRYPTO_LIBRARY])

AC_OUTPUT(src/c/Makefile src/c/luacrypto/Makefile src/c/lbase64/Makefile src/c/lua-cjson/Makefile \
          etc/openssl-cert/Makefile Makefile)
