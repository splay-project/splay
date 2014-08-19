BASE_IP="172.16.0."
FILE=$1
DEST=$2
machines=( $(seq 99 118) ) 

for m in ${machines[@]} 
do
	echo $BASE_IP$m
	scp -p $FILE  splayd@$BASE_IP$m:$DEST
done


