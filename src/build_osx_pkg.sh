#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: ./build_osx_pkg.sh VER"
	exit
fi

cd osx-installer/
./update_content_pkg.sh ${VER}
cd ..

/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker --doc osx-installer/splay.pmdoc --out splayd_${VER}.pkg