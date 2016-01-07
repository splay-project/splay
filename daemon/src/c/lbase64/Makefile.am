#dist_data_DATA=test.lua
if luabase64
  bin_PROGRAMS       =lbase64.so
  lbase64_so_SOURCES =lbase64.c

if lua_headers
  lbase64_so_CPPFLAGS=-I$(LUA_HEADERS)
endif

  lbase64_so_CFLAGS  =$(cflags)
  lbase64_so_LDFLAGS =-shared $(linker_flags)
endif
