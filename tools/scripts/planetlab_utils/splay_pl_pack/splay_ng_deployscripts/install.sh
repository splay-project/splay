#!/bin/bash

# ps aux | grep my_ssh_config | cut -c10-14

if [[ $1 == "" ]]; then
	echo "${0} <node file> [<install type>]"
	exit
fi

if [[ $2 == "" ]]; then
	type="standard"
else
	type=$2
fi

if [[ $type != "standard" && $type != "dev" ]]; then
	echo "install type not recognized"
	exit
fi
echo "Install type: ${type}"

rm -fr logs
mkdir logs
 
# rm my_known_hosts
# touch my_known_hosts

for h in `cat $1`; do
	./host_install.sh $h $type > logs/$h.log 2>&1 &
	sleep 1
done

echo FINISHED
