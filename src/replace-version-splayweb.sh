#!/bin/bash
if [[ $1 == "" ]]; then
	echo "Usage: ./replace-version-splayweb.sh NEW_VERSION"
	exit
fi
new_version=$1

find splayweb -name "*.rb" -exec ./change-header-splayweb.sh {} ${new_version} \;