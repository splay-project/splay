#!/bin/bash
cmd=$1
readarray machines < cluster_hosts.txt  #requires Bash >= 4.0
for m in ${machines[@]} 
do
        echo "# Executing command on host $m #"
        ssh $m  "nohup bash -c '$cmd'" &
        echo ""
done
