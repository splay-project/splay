#!/bin/bash

# ps aux | grep my_ssh_config | cut -c10-14 | xargs kill

if [[ $1 == "" ]]; then
	echo "${0} <node file>"
	exit
fi
type="standard"

if [[ $type != "standard" ]]; then
	echo "install type not recognized"
	exit
fi
echo "Install type: ${type}"

rm -fr logs
mkdir logs

# what is the utility of this???
rm -f my_known_hosts
touch my_known_hosts

for h in `cat $1`; do
	echo "Installing on: $h"
	./host_install.sh $h $type > logs/$h.log 2>&1 &
	sleep 1
done

echo FINISHED
