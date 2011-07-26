#!/bin/bash

if [[ $1 == "" ]]; then
	echo "${0} <node file>"
	exit
fi

h=$1

mkdir -p logs/
rm -rf logs/*

slice="unineple_splay"

echo "Stopping SPLAY deamons in slice ${slice}"

for h in `cat $1`; do
	echo "Stopping : $h"
	ssh -o StrictHostKeyChecking=no -i ./planetlab-key ${slice}@$h "sudo /etc/init.d/./vinit.slice --stop" > logs/$h.log 2>&1 &	
	sleep 1
done

