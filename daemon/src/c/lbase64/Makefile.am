LIBS=
install_datadir=$(prefix)/share/lbase64
install_data_DATA=README test.lua
dist_data_DATA=README test.lua
if luabase64
  bin_PROGRAMS       =base64.so
  base64_so_SOURCES =lbase64.c

if lua_headers
  base64_so_CPPFLAGS=-I$(LUA_HEADERS)
endif

  base64_so_CFLAGS  =$(cflags)
  base64_so_LDFLAGS =-shared $(linker_flags)
endif
