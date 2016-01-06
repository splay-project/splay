LIBS=
bin_PROGRAMS     =cjson.so
cjson_so_SOURCES =lua_cjson.c strbuf.c fpconv.c

if lua_headers
  cjson_so_CPPFLAGS=-I$(LUA_HEADERS)
endif

cjson_so_CFLAGS  =-fpic
cjson_so_LDFLAGS =-shared
