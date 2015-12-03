#!/bin/bash
sudo apt-get update #safer
sudo apt-get install -y git build-essential libreadline-dev libncurses5-dev \
lua5.1 liblua5.1-0 liblua5.1-0-dev lua-socket lua-socket-dev \
libssl-dev lua-sec lua-sec-dev 

echo "SPLAY_PATH=\"$HOME/local/lualibs/lib/?.lua\"" 			>> ~/.profile
echo "SPLAY_CPATH=\"$HOME/local/lualibs/clib/?.so\""			>> ~/.profile
echo "DEFAULT_LUA_PATH=\"`lua -e \"print( package.path)\"`\"" 	>> ~/.profile
echo "DEFAULT_LUA_CPATH=\"`lua -e \"print( package.cpath)\"`\"" >> ~/.profile
echo "LUA_PATH=\"\$SPLAY_PATH;\$DEFAULT_LUA_PATH\"" 			>> ~/.profile
echo "LUA_CPATH=\"\$SPLAY_CPATH;\$DEFAULT_LUA_CPATH\""  		>> ~/.profile
echo "export LUA_PATH"											>> ~/.profile
echo "export LUA_CPATH"											>> ~/.profile

git clone https://github.com/splay-project/splay.git
cd splay/src/external_libs/lua-5.1.4/ || exit;
make linux
cd ../../daemon/ || exit;
make
bash -l install.sh
