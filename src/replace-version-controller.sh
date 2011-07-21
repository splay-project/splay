#!/bin/bash

if [[ $1 == "" ]]; then
	echo "Usage: ./replace-version-controller.sh NEW_VERSION"
	exit
fi

new_version=$1

find controller -name "*.rb" -exec ./change-header-controller.sh {} ${new_version} \;