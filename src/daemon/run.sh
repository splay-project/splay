#!/bin/bash

# example script to run 50 splayd on localhost

for n in `seq 50`; do
	let "start_port = 30000 + $n * 100"
	let "end_port = start_port + 99"
	#lua splayd.lua local$n localhost 11000 $start_port $end_port > /dev/null 2>&1 &
	lua splayd.lua local$n localhost 11000 $start_port $end_port > splayd_$n.log 2>&1 &
done

# or you can directly run jobs
#for n in `seq 100`; do
#  ./jobd jobs/job_file > /dev/null 2>&1 & 
#done
