#!/bin/bash
for ((size = 2048 ; size < 2000000 ; size=size*2))
do
	echo "Size $size"
	lua client.lua 10.0.2.18 5000 $size 1000
done
