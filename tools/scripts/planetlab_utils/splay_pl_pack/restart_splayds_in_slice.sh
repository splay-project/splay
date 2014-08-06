#!/bin/bash

if [[ $1 == "" ]]; then
	echo "${0} <node file>"
	exit
fi

h=$1

mkdir -p logs/
rm -rf logs/*

slice="unineple_splay_vs"

echo "Restarting SPLAY deamons in slice ${slice}"

for h in `cat $1`; do
	echo "Restarting  on: $h"
	ssh -t -t -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa_unineple_splay_vs  ${slice}@$h "bash sudo /etc/init.d/./vinit.slice --restart" > logs/$h.log 2>&1 &	
	sleep 1
done

