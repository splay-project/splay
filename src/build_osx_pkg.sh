#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: ./build_osx_pkg.sh VER"
	exit
fi

cd osx-installer/
./update_content_pkg.sh ${VER}
cd ..

pkgbuild --identifier org.splay-project.splayd --version 1.3 --root osx-installer/PKG_PAYLOAD  --install-location /Applications --scripts osx-installer/scripts  splayd_1.3.pkg
#pkgbuild --identifier org.splay-project.splayd --version 1.3 --root osx-installer/PKG_PAYLOAD  --install-location /Applications splayd_1.3.pkg
