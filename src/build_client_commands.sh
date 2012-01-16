#!/bin/bash
VER=$1
if [[ $VER == "" ]]; then
	echo "Usage: build_client_commands.sh VER"
	exit
fi
mkdir splay_client_commands_${VER}
cp -R rpc_client/* splay_client_commands_${VER}
cp AUTHORS splay_client_commands_${VER}/
COPY_EXTENDED_ATTRIBUTES_DISABLE=true COPYFILE_DISABLE=true tar czvf "splay_client_commands_${VER}.tar.gz" --exclude=.svn -X exclude_from_splay_client_commands.txt splay_client_commands_${VER}
rm -rf splay_client_commands_${VER}

