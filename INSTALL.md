Compile and install the Splay libraries on Linux
===

git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon 
make -f Makefile (for x86/amd64 architectures)
make -f Makefile.macosx (for OSX)


Compile and install the Splay libraries on Linux
===

git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make macosx 
cd ../../daemon 
cd splay/src/daemon
make -f Makefile.macosx 

