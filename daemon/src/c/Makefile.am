LIBS=
bin_PROGRAMS=splayd jobd splay_core.so misc_core.so data_bits_core.so
splayd_SOURCES           =splayd.c splay_lib.c
jobd_SOURCES             =jobd.c splay_lib.c
splay_core_so_SOURCES    =splay.c
splay_core_so_CFLAGS     =-fpic
splay_core_so_LDFLAGS    =-shared
misc_core_so_SOURCES     =misc.c
misc_core_so_CFLAGS      =-fpic
misc_core_so_LDFLAGS     =-shared -lm
data_bits_core_so_SOURCES=data_bits.c
data_bits_core_so_CFLAGS =-fpic
data_bits_core_so_LDFLAGS=-shared -lm
if lua_headers
  splayd_CPPFLAGS           =-I$(LUA_HEADERS)
  jobd_CPPFLAGS             =-I$(LUA_HEADERS)
  splay_core_so_CPPFLAGS    =-I$(LUA_HEADERS)
  misc_core_so_CPPFLAGS     =-I$(LUA_HEADERS)
  data_bits_core_so_CPPFLAGS=-I$(LUA_HEADERS)
endif
if lua_lib
  splayd_LDADD              =-L$(LUA_LIBRARY) -llua5.1
  jobd_LDADD                =-L$(LUA_LIBRARY) -llua5.1
else
  splayd_LDADD              =-llua5.1
  jobd_LDADD                =-llua5.1
endif
