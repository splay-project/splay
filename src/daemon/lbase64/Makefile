# makefile for base64 library for Lua

# change these to reflect your Lua installation
#LUA= /opt/local/
#LUAINC= $(LUA)/include
#LUALIB= $(LUA)/lib
#LUABIN= $(LUA)/bin

# these will probably work if Lua has been installed globally
LUA= /usr
LUAINC= $(LUA)/include/lua5.1/
LUALIB= $(LUA)/lib/x86_64-linux-gnu/
LUABIN= $(LUA)/bin/

# probably no need to change anything below here
CC= gcc
CFLAGS= $(INCS) $(WARN) -O2 $G -fPIC
WARN= -ansi -pedantic -Wall
INCS= -I$(LUAINC)
MAKESO= $(CC) -shared -fPIC
#MAKESO= env MACOSX_DEPLOYMENT_TARGET=10.3 $(CC) -bundle -undefined dynamic_lookup

MYNAME= base64
MYLIB= l$(MYNAME)
T= $(MYNAME).so
OBJS= $(MYLIB).o
TEST= test.lua

all:	test

test:	$T
	$(LUABIN)/lua $(TEST)

o:	$(MYLIB).o

so:	$T

$T:	$(OBJS)
	$(MAKESO) -o $@ $(OBJS)

clean:
	rm -f $(OBJS) $T core core.*

doc:
	@echo "$(MYNAME) library:"
	@fgrep '/**' $(MYLIB).c | cut -f2 -d/ | tr -d '*' | sort | column

# distribution

FTP= www:www/ftp/lua/5.1
F= http://www.tecgraf.puc-rio.br/~lhf/ftp/lua/5.1/$A
D= $(MYNAME)
A= $(MYLIB).tar.gz
TOTAR= Makefile,README,$(MYLIB).c,test.lua

distr:	clean
	tar zcvf $A -C .. $D/{$(TOTAR)}
	touch -r $A .stamp
	scp -p $A $(FTP)

diff:	clean
	wget -q -N $F
	tar zxf $A
	diff $D .

# eof
