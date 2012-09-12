#!/bin/bash
for i in `ps aux | grep "lua splayd.lua" | grep -v "grep" | sed s/'  *'/' '/g | cut -d' ' -f2`
do
	kill -9 $i
done