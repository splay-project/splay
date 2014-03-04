#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: ./build_osx_pkg.sh VER"
	exit
fi

cd osx-installer/
./update_content_pkg.sh ${VER}
cd ..

pkgbuild --identifier org.splay-project.splayd.pkg --root osx-installer/SPLAY/ --install-location /Applications ./splayd_${VER}.pkg

