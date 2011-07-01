#!/bin/bash

new_version=$1

find rpc_client -name "*.lua" -exec ./change-header-client-commands.sh {} ${new_version} \;
