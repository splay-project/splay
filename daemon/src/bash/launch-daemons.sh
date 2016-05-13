#!/bin/bash - 
#===============================================================================
#
#          FILE: launch-daemons.sh
# 
#         USAGE: ./launch-daemons.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 05/13/2016 16:46
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
here=`pwd`
echo "Launching Splay daemons..."
for d in `ls | grep Daemon` ; do
  cd $d
  echo -e "\tExecution of $d ..."
  splayd &>log &
  pid=$!
  echo -e "\twith process ID: $pid"
  cd $here
done
echo "DONE"
