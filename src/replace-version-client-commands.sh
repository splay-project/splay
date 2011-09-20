#!/bin/bash
if [[ $1 == "" ]]; then
	echo "Usage: ./replace-version-client-commands.sh NEW_VERSION"
	exit
fi
new_version=$1

find rpc_client -name "*.lua" -exec ./change-header-client-commands.sh {} ${new_version} \;
