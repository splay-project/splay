#!/opt/local/bin/bash
readarray machines < cluster_hosts.txt  #requires Bash >= 4.0
USERNAME=splayd
PASSWD=splayd
for m in ${machines[@]} 
do
	./ssh-copy-id.expect $m $USERNAME $PASSWD ~/.ssh/id_rsa.pub	
done

