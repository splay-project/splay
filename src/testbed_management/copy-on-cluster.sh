#!/opt/local/bin/bash
readarray machines < cluster_hosts.txt  #requires Bash >= 4.0
FILE=$1
DEST=$2
for m in ${machines[@]} 
do
	echo $m
	scp -p $FILE $m:$DEST
done


