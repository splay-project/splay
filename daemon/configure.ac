#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
AC_INIT([splay-daemon], [1.0], [raziel.carvajal@unine.ch])
AM_INIT_AUTOMAKE
AM_CONFIG_HEADER(config.h)
CPPFLAGS='-I../../include'
AC_PROG_CC

AC_CHECK_PROG([HAVE_LUA], [lua], [true], [false])
if test x$HAVE_LUA = xtrue ; then
  AC_MSG_CHECKING([Lua is installed])
else
  AC_MSG_CHECKING([Lua is not installed. Splay-deamon requires lua, please\
    install it after the built])
fi

AC_CHECK_PROG([HAVE_OPENSSL], [openssl], [true], [false])
if test x$HAVE_OPENSSL = xtrue ; then
  AC_MSG_CHECKING([OpenSsl is installed])
else
  AC_MSG_ERROR([OpenSsl is not installed. Splay-deamon requires OpenSsl\
    to be built, please install OpenSsl and do ./configure again])
fi

AC_CHECK_HEADERS([arpa/inet.h fcntl.h 'netinet/in.h' stdlib.h\
  string.h sys/socket.h unistd.h])
AC_CHECK_HEADERS(['lua5.1/lua.h' 'lua5.1/lualub.h' 'lua5.1/luaxlib.h'])

AC_TYPE_SIZE_T
AC_SEARCH_LIBS(lua_close, ['lua5.1' 'lua5.2'],
  [
   #AC_CHECK_HEADERS(['lua5.1/lua.h' 'lua5.1/lualub.h' 'lua5.1/luaxlib.h'])
  ],
  [AC_MSG_ERROR([liblua is not installed])])
AC_SEARCH_LIBS(SSL_accept, [ssl],
  [],
  [AC_MSG_ERROR([libssl is not installed])])
AC_SEARCH_LIBS(DSA_new, [crypto],
  [],
  [AC_MSG_ERROR([libcrypto is not installed])])

AC_ARG_ENABLE([luabase64],
  AS_HELP_STRING([--enable-luabase64],[Compile base64 library for Lua5.2]),
  [case "${enableval}" in\
     yes) luabase64=true ;;\
     no)  luabase64=false ;;\
     *) AC_MSG_ERROR([You must type yes OR no in value for --enable-luabase64]) ;;\
   esac],
  [compile_luabase64=false])
AM_CONDITIONAL([luabase64],[test x$luabase64 = xtrue])

AC_FUNC_REALLOC
AC_OUTPUT(Makefile src/c/Makefile src/c/luacrypto/Makefile\
          src/c/lbase64/Makefile src/c/lua-cjson/Makefile)
