LIBS=
bin_PROGRAMS=crypto.so
crypto_so_SOURCES =lcrypto.c
crypto_so_CFLAGS  =-fpic
crypto_so_LDFLAGS =-shared
if lua_headers
  crypto_so_CPPFLAGS=-I$(LUA_HEADERS)
endif
if crypto_lib
  crypto=-L$(CRYPTO_LIBRARY) -lcrypto
else
  crypto=-lcrypto
endif
if ssl_lib
  ssl=-L$(OPENSSL_LIBRARY) -lssl
else
  ssl=-lssl
endif
crypto_so_LDADD   =$(crypto) $(ssl)
