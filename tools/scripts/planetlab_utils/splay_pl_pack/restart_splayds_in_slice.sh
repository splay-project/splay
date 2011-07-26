#!/bin/bash

if [[ $1 == "" ]]; then
	echo "${0} <node file>"
	exit
fi

h=$1

slice="unineple_splay"

echo "Restarting SPLAY deamons in slice ${slice}"

for h in `cat $1`; do
	echo "Installing on: $h"
	ssh -o StrictHostKeyChecking=no -i ./planetlab-key ${slice}@$h "sudo /etc/init.d/./vinit.slice --restart" > logs/$h.log 2>&1 &	
	sleep 1
done

