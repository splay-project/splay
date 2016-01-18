LIBS=
bin_PROGRAMS=splayd jobd splay_core.so misc_core.so data_bits_core.so
splayd_SOURCES           =splayd.c splay_lib.c
jobd_SOURCES             =jobd.c splay_lib.c
splay_core_so_SOURCES    =splay.c
splay_core_so_CFLAGS     =$(cflags)
splay_core_so_LDFLAGS    =-shared -lm $(linker_flags)
misc_core_so_SOURCES     =misc.c
misc_core_so_CFLAGS      =$(cflags)
misc_core_so_LDFLAGS     =-shared -lm $(linker_flags)
data_bits_core_so_SOURCES=data_bits.c
data_bits_core_so_CFLAGS =$(cflags)
data_bits_core_so_LDFLAGS=-shared -lm $(linker_flags)

if lua_headers
  splayd_CPPFLAGS           =-I$(LUA_HEADERS)
  jobd_CPPFLAGS             =-I$(LUA_HEADERS)
  splay_core_so_CPPFLAGS    =-I$(LUA_HEADERS)
  misc_core_so_CPPFLAGS     =-I$(LUA_HEADERS)
  data_bits_core_so_CPPFLAGS=-I$(LUA_HEADERS)
endif

if lua_lib
  splayd_LDADD              =-L$(LUA_LIBRARY) $(linker_flags) $(llua)
  jobd_LDADD                =-L$(LUA_LIBRARY) $(linker_flags) $(llua)
else
  splayd_LDADD              =$(linker_flags) $(llua)
  jobd_LDADD                =$(linker_flags) $(llua)
endif
