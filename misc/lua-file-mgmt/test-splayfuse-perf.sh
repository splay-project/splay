#!/bin/bash

if [ $# -lt 3 ]
then
	echo "Syntax: .test-splayfuse-perf.sh <number_of_tests> <lua_operation> FILE1 [FILE2]"
	echo ""
	echo "lua_operation can be: luacp, luacp_2MB_blocks, luaread, luaread_2MB_blocks"
	echo "luacp, luacp_2MB_blocks need an extra argument for FILE2"
	exit
fi

n=$1
luaop=$2
filename1=$3

if [ "$luaop" = "luacp" ] || [ "$luaop" = "luacp_2MB_blocks" ]
then
	if [ $# -ne 4 ]
	then
		echo "Syntax: .test-splayfuse-perf.sh <number_of_tests> <lua_operation> FILE1 [FILE2]"
		echo ""
		echo "lua_operation can be: luacp, luacp_2MB_blocks, luaread, luaread_2MB_blocks"
		echo "luacp, luacp_2MB_blocks need an extra argument for FILE2"
		exit
	else
		filename2=$4
	fi
fi

for i in $(seq 1 $n)
do
	echo "Executing \"./${luaop} $filename1 $filename2 >> results_${luaop}.txt\" for the ${i}th time"
	./${luaop} $filename1 $filename2 >> results_${luaop}.txt
	if [ -n "$filename2" ]
	then
		rm $filename2
	fi
done
