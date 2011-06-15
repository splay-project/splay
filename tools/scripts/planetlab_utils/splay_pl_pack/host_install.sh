#!/bin/bash

# TODO special ssh config file, removing known_hosts each time to avoid key
# changes.

if [[ $1 == "" ]]; then
	echo "${0} <hostname>"
	exit
fi

h=$1

url="http://splay2.unineuchatel.ch/"
script="local_install.sh"

# $RANDOM to protect against proxy/cache
script_t="local_install.sh?$RANDOM"
slice="unineple_splay"

echo "Install on ${1} (${slice})"

ssh -o StrictHostKeyChecking=no -i ./planetlab-key ${slice}@$h "rm -f ${script}; wget ${url}${script_t}; mv ${script_t} ${script}; chmod 755 ${script}; ./${script}"

