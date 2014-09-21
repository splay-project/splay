#!/bin/bash
BASE_IP="172.16.0."
cmd=$1
machines=( $(seq 99 118) ) 

for m in ${machines[@]} 
do
	echo -n "$BASE_IP$m "
	ssh splayd@$BASE_IP$m bash <<< "$cmd"  
done

