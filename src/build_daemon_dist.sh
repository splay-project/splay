#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: build_daemondist.sh VER"
	exit
fi
mkdir splayd_${VER}
cp -R daemon/* splayd_${VER}/
cp AUTHORS splayd_${VER}/
COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splayd_${VER}.tar.gz" -X exclude.txt --exclude=.svn splayd_${VER}/
rm -rf splayd_${VER}
