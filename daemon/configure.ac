#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.
AC_INIT([splayLib], [1.0], [raziel.carvajal@unine.ch])
AM_INIT_AUTOMAKE
AM_CONFIG_HEADER(config.h)
AC_PROG_CC
# Checks for header files.
AC_CHECK_HEADERS([arpa/inet.h fcntl.h netinet/in.h stdlib.h string.h sys/socket.h unistd.h])
# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_SIZE_T
# Checks for library functions.
AC_CHECK_LIB([lua5.1], [lua_close], [], [AC_MSG_ERROR([Unable to find LibLua])])
AC_FUNC_REALLOC
AC_OUTPUT(Makefile)
