#!/bin/bash
BASE_IP="172.16.0."
cmd=$1
machines=( 2 3 4 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ) 

for m in ${machines[@]} 
do
	echo -n "$BASE_IP$m "
	ssh splayd@$BASE_IP$m bash <<< "$cmd"  
done

