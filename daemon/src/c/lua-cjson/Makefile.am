dist_data_DATA=LICENSE lua-cjson.spec dtoa.c g_fmt.c
LIBS=
bin_PROGRAMS     =cjson.so
cjson_so_SOURCES =lua_cjson.c strbuf.c fpconv.c fpconv.h  strbuf.h \
  dtoa_config.h

if lua_headers
  cjson_so_CPPFLAGS=-I$(LUA_HEADERS)
endif

cjson_so_CFLAGS  =$(cflags)
cjson_so_LDFLAGS =-shared $(linker_flags)
