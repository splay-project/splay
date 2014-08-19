BASE_IP="172.16.0."
USERNAME=splayd
PASSWD=splayd
machines=( $(seq 99 118) ) 

for m in ${machines[@]} 
do
	./ssh-copy-id.expect $BASE_IP$m $USERNAME $PASSWD ~/.ssh/id_rsa.pub	
done

