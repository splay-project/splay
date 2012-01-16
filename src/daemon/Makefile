CC= gcc

# Since Lua 5.1, lua and lualib are merged.
#INCLUDE= -I/usr/include/lua5.1 -I/usr/local/openssl/include
INCLUDE= -I/usr/include/lua5.1

# For static linking, but loading dynamic modules will not work then.
#LIBS= -L/usr/lib -llua5.1 -lm -ldl
LIBS= -L/usr/lib -llua5.1 -lm
OPENSSL_LIBS= -L/usr/local/openssl/lib -lcrypto -lssl

#CFLAGS = -Wall -g -pedantic -DDEBUG $(INCLUDE)
CFLAGS= -Wall -O2 -pedantic $(INCLUDE)

.PHONY: all, clean

all: splayd jobd splay_core.so misc_core.so data_bits_core.so luacrypto/crypto.so cert lbase64/base64.so

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
	rm lbase64/*.o
	rm lbase64/*.so

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
	strip splayd

jobd: jobd.o splay_lib.o
	$(CC) -o jobd jobd.o splay_lib.o $(LIBS)
	strip jobd

### Splay module
splay_core.so: splay.o
	$(CC) -O -fpic -shared -o splay_core.so splay.o -lm
	strip splay_core.so

splay.o: splay.c splay.h
	$(CC) -fpic $(CFLAGS) -c -o splay.o splay.c

### Misc module
misc_core.so: misc.o
	$(CC) -O -fpic -shared -o misc_core.so misc.o -lm
	strip misc_core.so

misc.o: misc.c misc.h
	$(CC) -fpic $(CFLAGS) -c -o misc.o misc.c

### Data_bits module
data_bits_core.so: data_bits.o
	$(CC) -O -fpic -shared -o data_bits_core.so data_bits.o -lm
	strip data_bits_core.so

data_bits.o: data_bits.c data_bits.h
	$(CC) -fpic $(CFLAGS) -c -o data_bits.o data_bits.c

### luacrypto
luacrypto/crypto.so: luacrypto/crypto.o
	$(CC) -O -fpic -shared -o luacrypto/crypto.so luacrypto/*.o $(OPENSSL_LIBS)
	strip luacrypto/crypto.so

luacrypto/crypto.o: luacrypto/lcrypto.c luacrypto/lcrypto.h
	$(CC) -fpic $(CFLAGS) -c -o luacrypto/crypto.o luacrypto/lcrypto.c

### base64
lbase64/base64.so: lbase64/lbase64.o
	$(CC) -O -fpic -shared -o lbase64/base64.so lbase64/lbase64.o
	strip lbase64/base64.so
lbase64/lbase64.o: lbase64/lbase64.c
	$(CC) -fpic $(CFLAGS) -c -o lbase64/lbase64.o lbase64/lbase64.c
