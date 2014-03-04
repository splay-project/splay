#!/bin/bash
#Update the content of the pkg by downloading the requested version
#from the splay website and copying the files in the right places.

VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: update_content_pkg.sh VER"
	exit
fi

#wget http://www.splay-project.org/splay/release/splayd_${VER}.tar.gz
cp ../splayd_${VER}.tar.gz .
tar xzvf splayd_${VER}.tar.gz
cd splayd_${VER}
make -f Makefile.macosx splayd jobd splay_core.so misc_core.so data_bits_core.so luacrypto/crypto.so 
cd ..

cp splayd_${VER}/splayd PKG_PAYLOAD/SPLAY/dist/
cp splayd_${VER}/splayd.lua PKG_PAYLOAD/SPLAY/dist/
cp splayd_${VER}/jobd PKG_PAYLOAD/SPLAY/dist/
cp splayd_${VER}/jobd.lua PKG_PAYLOAD/SPLAY/dist/
cp splayd_${VER}/settings.lua PKG_PAYLOAD/SPLAY/dist/

cp splayd_${VER}/splay_core.so PKG_PAYLOAD/SPLAY/clibs/
cp splayd_${VER}/misc_core.so PKG_PAYLOAD/SPLAY/clibs/splay/
cp splayd_${VER}/data_bits_core.so PKG_PAYLOAD/SPLAY/clibs/splay/
cp splayd_${VER}/luacrypto/crypto.so PKG_PAYLOAD/SPLAY/clibs/splay/

cp splayd_${VER}/modules/json.lua PKG_PAYLOAD/SPLAY/lualibs/
cp splayd_${VER}/modules/splay.lua PKG_PAYLOAD/SPLAY/lualibs/
cp splayd_${VER}/modules/splay/*lua PKG_PAYLOAD/SPLAY/lualibs/splay/

rm -rf splayd_${VER}.tar.gz
rm -rf splayd_${VER}/
