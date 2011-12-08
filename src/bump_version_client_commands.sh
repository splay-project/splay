#!/bin/bash
# cat replace-version-client-commands.sh 
if [[ $1 == "" ]]; then
	echo "Usage: ./bump_version_client_commands.sh NEW_VERSION"
	exit
fi
new_version=$1
find rpc_client -name "*.lua" | xargs  sed -i "" s/'Splay Client Commands ### v..* ###'/"Splay Client Commands ### v${new_version} ###"/ 
