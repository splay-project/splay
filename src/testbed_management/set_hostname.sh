#!/bin/bash

readarray machines < cluster_hosts.txt  #requires Bash >= 4.0

for m in ${machines[@]} 
do
	echo -n "$m "
	ssh $m bash <<< "sudo hostname splayd-$m && sudo echo splayd-$m > /etc/hostname" 
done

