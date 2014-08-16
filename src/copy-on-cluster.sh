BASE_IP="172.16.0."
FILE=$1
DEST=$2
machines=( 2 3 4 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ) 

for m in ${machines[@]} 
do
	echo $BASE_IP$m
	scp -p $FILE  splayd@$BASE_IP$m:$DEST
done


