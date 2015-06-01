# Makefile for SPLAY using Mac OS X

CC= gcc

######## EDIT #######

# HEADERS
# For MacPorts installed libraries (default)
INCLUDE= -I/opt/local/lib/openssl97/include/ -I/opt/local/include/

# LIBRARIES
# For static linking, but loading dynamic modules will not work then.
#LIBS= -L/usr/lib -llua.5.1 -lm -ldl
# For MacPorts installed libraries (default)
LIBS= -L/opt/local/lib -llua -lm

# OPENSSL
# For MacPorts installed libraries (default)
OPENSSL_LIBS= -L/opt/local/lib/openssl97/lib/ -lcrypto -lssl

######## DO NOT EDIT #######

#CFLAGS = -Wall -g -pedantic -DDEBUG $(INCLUDE)
CFLAGS= -Wall -O2 -pedantic $(INCLUDE)

.PHONY: all, clean

all: splayd jobd splay_core.so misc_core.so data_bits_core.so luacrypto/crypto.so lbase64/base64.so lua-cjson/cjson.so cert

clean:
	rm -f *~
	rm -fr .deps
	rm -f *.o *.so
	rm -f *.log
	rm -f *.pem *.srl
	rm -f splayd jobd
	rm -fr jobs
	rm -fr jobs_fs
	rm -fr logs
	rm luacrypto/*.o
	rm luacrypto/*.so
	rm lua-cjson/*.o
	rm lua-cjson/*.so

cert:
	#openssl genrsa -out key.pem 1024
	#openssl req -new -key key.pem -out request.pem
	#openssl req -x509 -days 30 -key key.pem -in request.pem -out client.pem
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

splayd.o: splayd.c splayd.h
	$(CC) $(CFLAGS) -c -o splayd.o splayd.c

jobd.o: jobd.c jobd.h
	$(CC) $(CFLAGS) -c -o jobd.o jobd.c

splay_lib.o: splay_lib.c splay_lib.h
	$(CC) $(CFLAGS) -c -o splay_lib.o splay_lib.c

splayd: splayd.o splay_lib.o
	$(CC) -o splayd splayd.o splay_lib.o $(LIBS)

jobd: jobd.o splay_lib.o
	$(CC) -o jobd jobd.o splay_lib.o $(LIBS)

splay_core.so: splay.o
	$(CC) -O -fno-common -dynamiclib -o splay_core.so splay.o -undefined dynamic_lookup 

splay.o: splay.c splay.h
	$(CC) -fno-common $(CFLAGS) -c -o splay.o splay.c

### Misc module
misc_core.so: misc.o
	$(CC) -O -fno-common -dynamiclib -undefined dynamic_lookup -lm -o misc_core.so misc.o

misc.o: misc.c misc.h
	$(CC) -fno-common $(CFLAGS) -c -o misc.o misc.c

### Data_bits module
data_bits_core.so: data_bits.o
	$(CC) -O -fno-common -dynamiclib -undefined dynamic_lookup -lm -o data_bits_core.so data_bits.o

data_bits.o: data_bits.c data_bits.h
	$(CC) -fno-common $(CFLAGS) -c -o data_bits.o data_bits.c

### luacrypto
luacrypto/crypto.so: luacrypto/crypto.o
	$(CC) -O -fno-common -dynamiclib -undefined dynamic_lookup -lm -o luacrypto/crypto.so luacrypto/*.o $(OPENSSL_LIBS)
	# strip luacrypto/crypto.so

luacrypto/crypto.o: luacrypto/lcrypto.c luacrypto/lcrypto.h
	$(CC) -fno-common $(CFLAGS) -c -o luacrypto/crypto.o luacrypto/lcrypto.c

### base64
lbase64/base64.so: lbase64/lbase64.o
	$(CC) -O -fno-common -dynamiclib -undefined dynamic_lookup -o lbase64/base64.so lbase64/lbase64.o
	#strip lbase64/base64.so
lbase64/lbase64.o: lbase64/lbase64.c
	$(CC) -fno-common $(CFLAGS) -c -o lbase64/lbase64.o lbase64/lbase64.c

## sendf
sendf.so: sendf.o
	$(CC) -O -fno-common -dynamiclib -undefined dynamic_lookup -lm -o sendf.so sendf.o

sendf.o: sendf.c sendf.h
	$(CC) -fno-common $(CFLAGS) -c -o sendf.o sendf.c

##lua-cjson
lua-cjson/cjson.so: lua-cjson/lua_cjson.o lua-cjson/strbuf.o lua-cjson/fpconv.o
	$(CC) -O -fpic -fno-common -dynamiclib -undefined dynamic_lookup -o lua-cjson/cjson.so lua-cjson/lua_cjson.o lua-cjson/strbuf.o lua-cjson/fpconv.o
	#strip lua-cjson/cjson.so
lua-cjson/strbuf.o:
	$(CC) -fpic $(CFLAGS) -c -o lua-cjson/strbuf.o lua-cjson/strbuf.c
lua-cjson/fpconv.o:
	$(CC) -fpic $(CFLAGS) -c -o lua-cjson/fpconv.o lua-cjson/fpconv.c
lua-cjson/lua_cjson.o: lua-cjson/lua_cjson.c
	$(CC) -fpic $(CFLAGS) -c -o lua-cjson/lua_cjson.o lua-cjson/lua_cjson.c
