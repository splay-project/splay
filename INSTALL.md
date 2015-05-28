Pre-requisites
===
<!---
Create two directories to install lua and native modules:
```
user$ mkdir -p local/lualibs/lib  
user$ mkdir -p local/lualibs/clib 
```
-->
Append the following at the bottom of your $HOME/.bashrc:
```bash
SPLAY_PATH="$HOME/local/lualibs/lib/?.lua"
SPLAY_CPATH="$HOME/local/lualibs/clib/?.so"
DEFAULT_LUA_PATH=`lua -e "print( package.path)"`
DEFAULT_LUA_CPATH=`lua -e "print( package.cpath)"`
LUA_PATH="$SPLAY_PATH;$DEFAULT_LUA_PATH"
LUA_CPATH="$SPLAY_CPATH;$DEFAULT_LUA_CPATH"
export LUA_PATH LUA_CPATH
```

This will append the installation paths of the Splay libraries to the default ones. Since it uses the Lua interpreter to get the current system's path, it can be executed only once Lua is installed (see below).

Instructions for x86/amd64
===

Instructions for Ubuntu 14.04 LTS.
Install the dependencies to compile and install Splay from source:

```bash
sudo apt-get install git build-essential libreadline-dev libncurses5-dev \
lua5.1 liblua5.1-0 liblua5.1-0-dev lua-socket lua-socket-dev \
libssl-dev lua-sec lua-sec-dev 
```

<!---
Execute:
```
user$ source ~/.bashrc
```
-->
Then, proceed with the following steps:
```bash
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make linux
cd ../../daemon/lua-cjson
make 
cd ../ 
make
source ~/.bashrc
./install.sh
```
<!--- 
mkdir -p local/lualibs/lib
mkdir -p local/lualibs/clib  
cp cjson.so ~/local/lualibs/clib/ 
-->
You are now ready to Splay!


Instructions for Mac OSX
===
TO_BE_UPDATED 
```
git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/
make macosx 
cd ../../daemon
make -f Makefile.macosx 
./install.sh
```


