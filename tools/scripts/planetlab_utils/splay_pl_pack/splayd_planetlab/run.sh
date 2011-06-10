#!/bin/bash

cd /home/*/splayd_planetlab
wd=`pwd`
echo "PWD = " $wd

# Specific splayd run file, for UNINE testing.

PATH=$PATH:${wd}/lua/src
LD_LIBRARY_PATH=${wd}/lua/src
export PATH LD_LIBRARY_PATH

LUA_PATH=${wd}/lualibs/lib/?.lua
LUA_CPATH=${wd}/lualibs/clib/?.so
export LUA_PATH LUA_CPATH

killall splayd

cd $wd/splayd
mkdir $wd/splayd/logs 2> /dev/null

# In production (+ production in splayd.lua)
#./splayd -d > /dev/null 2>&1 &
./splayd > ${wd}/splayd/logs/splayd.log 2>&1 &

# debug
#./splayd

# NOTE
# From shell, the script end after launching ./splayd -d, but from ssh, if we
# not add the & ssh stay connected.

