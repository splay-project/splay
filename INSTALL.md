Pre-requisites
===
These instructions assume these two directories exist to install lua and native modules:

```
~/local/lualibs/lib 
~/local/lualibs/clib
```

Instructions for x86/amd64
===

Instructions given for Ubuntu/Debian distributions.
Install the dependencies to compile and install Splay from source:

```
sudo apt-get install build-essential libreadline-dev
```

Then, proceed with the following steps:

```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon 
make -f Makefile
./install.sh
```

Instructions for Mac OSX
===
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make macosx 
cd ../../daemon
make -f Makefile.macosx 
./install.sh
```


