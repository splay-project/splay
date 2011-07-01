#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: build_ctrldist.sh VER"
	exit
fi
mkdir controller_${VER}
cp -R controller/* controller_${VER}/
cp AUTHORS controller_${VER}/
COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "controller_${VER}.tar.gz" -X exclude_from_ctrl.txt  --exclude=.svn controller_${VER}/
rm -rf controller_${VER}
