echo "1st param: planet_lab_hosts"
filename=$1
cat $filename |   # Supply input from a file.
while read line   # As long as there is another line to read ...
do
	echo "SSH'ing in $line"
	ssh -o "StrictHostKeyChecking no" -i planetlab-key unineple_splay@$line bash <<< 'exit'
done
