Pre-requisites
===
Create two directories to install lua and native modules:

```
user$ mkdir -p local/lualibs/lib  
user$ mkdir -p local/lualibs/clib 
```

Append the following at the bottom of your $HOME/.bashrc:
```
SPLAY_PATH="$HOME/local/lualibs/lib/?.lua"
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

Instructions for Ubuntu 14.04 LTS.
Install the dependencies to compile and install Splay from source:

```bash
sudo apt-get install git build-essential libreadline-dev libncurses5-dev\
lua5.1 liblua5.1-0 liblua5.1-0-dev lua-socket lua-socket-dev \
libssl-dev lua-sec lua-sec-dev 
```

Execute:
```
user$ source ~/.bashrc
```

Then, proceed with the following steps:

```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon/lua-cjson
make 
cp cjson.so ~/local/lualibs/clib/
cd ../ 
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


