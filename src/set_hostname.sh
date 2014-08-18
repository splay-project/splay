#!/bin/bash
BASE_IP="172.16.0."
machines=( $( seq 99 1 118 ) ) 

for m in ${machines[@]} 
do
	echo -n "$BASE_IP$m "
	ssh splayd@$BASE_IP$m bash <<< "sudo hostname splayd-$m && sudo echo splayd-$m > /etc/hostname" 
done

