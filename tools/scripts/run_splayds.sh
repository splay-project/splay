#!/usr/bin/env bash

if [[ $# -eq 0 ]]
then
	nbd=10
else
	nbd=$[$1]
fi

if [[ $nbd -ge 201 ]]
then
	echo "maximum number of splayd is 200"
	exit
fi

echo "running" $nbd "splayd locally"

cd splayds

for ((i=1;i<=$nbd;i++))
do
	cd splayd_$i/
	startport=$[12000+100*$i]
	stopport=$[11999+100*($i+1)]
	echo "Running splayd #$i with portrange $startport $stopport"
	# waiting 1 sec
	sleep 1
	lua splayd.lua d$i 127.0.0.1 11000 $startport $stopport &
	cd ..
done

cd ..

