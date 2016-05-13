SUBDIRS=src/c src/c/luacrypto src/c/lbase64 src/c/lua-cjson \
  etc/openssl-cert

install_datadir=$(prefix)
install_data_DATA=README.md
dist_data_DATA=README.md

test_splay-daemon:
	$(eval LUA=$(shell lua -e 'print(package.path)');$(prefix)/share/lua/?.lua)
	$(eval CLUA=$(shell lua -e 'print(package.cpath)');$(prefix)/bin/?.so)
	$(eval PATH=$(PATH):$(prefix)/bin)
	export LUA_PATH="$(LUA)" LUA_CPATH="$(CLUA)" PATH="$(PATH)" ; \
	  lua src/lua/install_check.lua

clone-daemons:
	./src/bash/clone-daemons.sh ${ARGS}
