#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
AC_INIT([splayLib], [1.0], [raziel.carvajal@unine.ch])
AM_INIT_AUTOMAKE
AM_CONFIG_HEADER(config.h)
CPPFLAGS=-I../../include
AC_PROG_CC
# Checks for header files.
AC_CHECK_HEADERS([arpa/inet.h fcntl.h netinet/in.h stdlib.h string.h sys/socket.h unistd.h])
# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_SIZE_T
# Checks for library functions.
AC_SEARCH_LIBS(lua_close, [lua5.1 lua5.2],
  [],
  [AC_MSG_ERROR([liblua is not installed])])
AC_CHECK_HEADER("/usr/include/lua5.1/lua.h",
  [CPPFLAGS="$CPPFLAGS -I/usr/include/lua5.1"],
  [AC_MSG_ERROR([Headers of Lua are not installed])])
AC_FUNC_REALLOC
AC_OUTPUT(Makefile src/c/Makefile)
