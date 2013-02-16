#!/bin/bash
if [[ $# -lt 4 ]]
then
	echo "Syntax: ${0} <ip prefix> <ip last octet> <port> <n_nodes>"
	exit 1
fi
ip_prefix=$1
base_last_oct=$2
base_port=$3
n_nodes=$4
base_port=`expr $base_port + 1`
if [[ $ip_prefix = "127.0.0" ]] && [[ $base_last_oct = "1" ]]
then
	for ((i = 0; i < n_nodes; i++ ))
	do
		((port = i * 2))
		((port = base_port + port))
		lua distdb-cli.lua $ip_prefix.$base_last_oct $port del_all
	done
else
	for ((i = 0; i < n_nodes; i++ ))
	do
		((last_oct = base_last_oct + i))
		lua distdb-cli.lua $ip_prefix.$last_oct $base_port del_all
	done
fi
exit 0
