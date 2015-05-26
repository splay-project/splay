Compile and install the Splay libraries on x86/amd64
===
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon 
make -f Makefile
```

Compile and install the Splay libraries on Mac OSX
===
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make macosx 
cd ../../daemon 
cd splay/src/daemon
make -f Makefile.macosx 
``

