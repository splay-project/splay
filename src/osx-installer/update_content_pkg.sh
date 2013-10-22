#!/bin/bash
#Update the content of the pkg by downloading the requested version
#from the splay website and copying the files in the right places.

VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: update_content_pkg.sh VER"
	exit
fi

wget http://www.splay-project.org/splay/release/splayd_${VER}.tar.gz
tar xzvf splayd_${VER}.tar.gz
cd splayd_${VER}
make -f Makefile.macosx splayd jobd splay_core.so misc_core.so data_bits_core.so luacrypto/crypto.so 
cd ..

cp splayd_${VER}/splayd SPLAY/dist/
cp splayd_${VER}/splayd.lua SPLAY/dist/
cp splayd_${VER}/jobd SPLAY/dist/
cp splayd_${VER}/jobd.lua SPLAY/dist/
cp splayd_${VER}/settings.lua SPLAY/dist/

cp splayd_${VER}/splay_core.so SPLAY/clibs/
cp splayd_${VER}/misc_core.so SPLAY/clibs/splay/
cp splayd_${VER}/data_bits_core.so SPLAY/clibs/splay/
cp splayd_${VER}/luacrypto/crypto.so SPLAY/clibs/splay/

cp splayd_${VER}/modules/json.lua SPLAY/lualibs/
cp splayd_${VER}/modules/splay.lua SPLAY/lualibs/
cp splayd_${VER}/modules/splay/*lua SPLAY/lualibs/splay/

rm -rf splayd_${VER}.tar.gz
rm -rf splayd_${VER}/