echo "1st param: planet_lab_hosts_file pl_ssh_id_rsa"
filename=$1
ssh_key=$2
cat $filename |   # Supply input from a file.
while read line   # As long as there is another line to read ...
do
	echo "SSH'ing in $line"
	ssh -o "StrictHostKeyChecking no" -i $2 unineple_splay_vs@$line bash <<< 'exit'
done
