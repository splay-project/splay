Pre-requisites
===
These instructions assume these two directories exist to install lua and native modules for the user that will instlal the libraries:

```
~/local/lualibs/lib 
~/local/lualibs/clib
```

Add the following to your ~/.bashrc:
```
SPLAY_PATH="$HOME/local/lualibs/lualib/?.lua"
SPLAY_CPATH="$HOME/local/lualibs/clib/?.so"
ST_PATH=`lua -e "print( package.path)"`
ST_CPATH=`lua -e "print( package.cpath)"`
if [[ "$ST_PATH" != *"$SPLAY_PATH"* ]]; then
  LUA_PATH="$SPLAY_PATH;$ST_PATH"
  LUA_CPATH="$SPLAY_CPATH;$ST_CPATH"
  export LUA_PATH LUA_CPATH
fi
```

Instructions for x86/amd64
===

Instructions given for Ubuntu/Debian distributions.
Install the dependencies to compile and install Splay from source:

```bash
sudo apt-get install build-essential libreadline-dev liblua5-1-socket2 liblua5.1-socket-dev libssl-dev liblua5.1-sec1
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


