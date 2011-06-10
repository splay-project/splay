#!/bin/bash

#L_PATH=/usr/share/lua/5.1
#L_CPATH=/usr/lib/lua/5.1
L_PATH=
L_CPATH=

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
echo
echo "Are you ready ? (y/n)"
read ready
if [[ $ready != "y" ]]; then
	exit
fi

echo "Lua libraries will go in $L_PATH."
echo "Lua C libraries will go in $L_CPATH."
echo "Is this correct ? (y/n)"
read correct
if [[ $correct != "y" ]]; then
	echo "Aborting installation, edit this file to fix good values."
	exit
fi
echo

echo "Installing Splay Lua libraries."

mkdir -p $L_PATH
mkdir -p $L_CPATH

cp modules/json.lua  $L_PATH/

mkdir $L_PATH/splay
cp modules/splay/*.lua $L_PATH/splay
rm $L_PATH/splay/splay.lua
cp modules/*.lua $L_PATH/

mkdir $L_CPATH/splay
cp splay.so $L_CPATH/splay_core.so
cp luacrypto/crypto.so $L_CPATH/crypto.so
cp misc.so $L_CPATH/splay/misc_core.so
cp data_bits.so $L_CPATH/splay/data_bits_core.so

echo
echo

lua install_check.lua
