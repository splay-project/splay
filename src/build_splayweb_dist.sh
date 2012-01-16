#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: build_splaywebdist.sh VER"
	exit
fi
mkdir splayweb_${VER}
cp -R splayweb/* splayweb_${VER}/
cp AUTHORS splayweb_${VER}/
COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splayweb_${VER}.tar.gz" -X exclude_from_splayweb.txt --exclude=.svn splayweb_${VER}/
rm -rf splayweb_${VER}
