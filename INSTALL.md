Pre-requisites
===
These instructions assume these two directories exist to install lua and native modules:

```
~/local/lualibs/lib 
~/local/lualibs/clib
```

Instructions for x86/amd64
===
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.2.3/
make linux
cd ../../daemon 
make -f Makefile
./install.sh
```

Instructions for Mac OSX
===
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.2.3/
make macosx 
cd ../../daemon
make -f Makefile.macosx 
./install.sh
```