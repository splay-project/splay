#mandatory
AC_INIT(poke.c)
AM_INIT_AUTOMAKE(poke, 1.0)
AM_CONFIG_HEADER(config.h:config.in)
AC_PROG_CC
#suffix (exe, o, etc...) is recognized automatically
AC_EXEEXT
AM_PROG_LIBTOOL
AC_HEADER_STDC
#just because utime it is used
AC_CHECK_HEADERS(utime.h)
AC_EGREP_HEADER(utimbuf, utime.h, AC_DEFINE(HAVE_STRUCT_UTIMBUF))
AC_FUNC_UTIME_NULL
#utime use
#list of Makefiles on each subdir at the project
AC_OUTPUT(Makefile)
