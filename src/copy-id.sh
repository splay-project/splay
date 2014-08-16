BASE_IP="172.16.0."
USERNAME=splayd
PASSWD=splayd
machines=( 2 3 4 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ) 
machines=( 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ) 

for m in ${machines[@]} 
do
	./ssh-copy-id.expect $BASE_IP$m $USERNAME $PASSWD ~/.ssh/id_rsa.pub	
done

