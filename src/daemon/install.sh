#!/bin/bash

if [[ $L_PATH == "" ]]; then
	echo "L_PATH not set, set it (LUA_PATH)."
	exit
fi
if [[ $L_CPATH == "" ]]; then
	echo "L_CPATH not set, set it (LUA_CPATH)."
	exit
fi

echo "This script will install Splay Lua modules and Lua C modules."
echo
echo "These are only Lua modules of the Splay package, for the installation"
echo "of the other modules (that can already be installed in your system), see"
echo "INSTALL."
echo
echo "You need to have already compiled splayd. If not see INSTALL."

echo "Lua libraries will go in $L_PATH."
echo "Lua C libraries will go in $L_CPATH."
echo "Installing Splay Lua libraries."

mkdir -p $L_PATH
mkdir -p $L_CPATH

cp modules/json.lua  $L_PATH/

mkdir -p $L_PATH/splay
cp modules/splay/*.lua $L_PATH/splay
rm -f $L_PATH/splay/splay.lua
cp modules/*.lua $L_PATH/

mkdir -p $L_CPATH/splay
cp splay_core.so $L_CPATH/
cp luacrypto/crypto.so $L_CPATH/crypto.so
cp misc_core.so $L_CPATH/splay/
cp data_bits_core.so $L_CPATH/splay/

lua install_check.lua
