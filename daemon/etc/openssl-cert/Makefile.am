install_datadir=$(prefix)/share/openssl-cert
dist_data_DATA=../../include ../../src/lua/modules/*.lua ../../src/lua/modules/splay \
	       ../../src/lua/*.lua client.cnf root.cnf ../../src/bash/*.sh

install:
	@echo "SPLAY-DAEMON INSTALLATION: Copying shared files ..."
	mkdir $(install_datadir)
	mkdir $(prefix)/bin/splay
	cp *.pem *.srl *.cnf $(install_datadir)
	cp -r ../../src/lua $(prefix)/share
	cp ../../src/bash/*.sh $(prefix)/share
	mv $(prefix)/share/lua/modules/* $(prefix)/share/lua
	rm $(prefix)/share/*.c $(prefix)/share/LICENSE $(prefix)/share/README \
		$(prefix)/share/lua-cjson.spec $(prefix)/share/test.lua
	rm -r $(prefix)/share/lua/modules
	mv $(prefix)/bin/misc_core.so $(prefix)/bin/data_bits_core.so $(prefix)/bin/splay
	@echo "SPLAY-DAEMON INSTALLATION: Updating your profile in file $(HOME)/$(user_prof) ..."
	$(eval LUA=$(shell lua -e 'print(package.path)');$(prefix)/share/lua/?.lua)
	$(eval CLUA=$(shell lua -e 'print(package.cpath)');$(prefix)/bin/?.so)
	$(eval PATH=$(PATH):$(prefix)/bin)
	@echo "export LUA_PATH='$(LUA)' LUA_CPATH='$(CLUA)' PATH='$(PATH)'">>$(HOME)/$(user_prof)
	@echo "SPLAY-DAEMON INSTALLATION: Installation of splay-daemon at $(prefix) is completed."

all: cert
cert:
	openssl req -newkey rsa:1024 -sha1 -keyout rootkey.pem -out rootreq.pem \
		-nodes -config ./root.cnf -days 365 -batch
	openssl x509 -req -in rootreq.pem -sha1 -extfile ./root.cnf \
  		-extensions v3_ca -signkey rootkey.pem -out root.pem -days 365
	openssl x509 -subject -issuer -noout -in root.pem
	openssl req -newkey rsa:1024 -sha1 -keyout key.pem -out req.pem \
  		-nodes -config ./client.cnf -days 365 -batch
	openssl x509 -req -in req.pem -sha1 -extfile ./client.cnf \
  		-extensions usr_cert -CA root.pem -CAkey rootkey.pem -CAcreateserial \
		-out cert.pem -days 365
	cat cert.pem root.pem > client.pem
	openssl x509 -subject -issuer -noout -in client.pem
