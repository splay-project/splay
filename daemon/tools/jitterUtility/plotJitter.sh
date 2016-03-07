#!/bin/bash - 
#===============================================================================
#
#          FILE: plotJitter.sh
# 
#         USAGE: ./plotJitter.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 02/18/2016 10:44
#      REVISION:  ---
#===============================================================================
set -o nounset                              # Treat unset variables as an error
rm -fr leaves leavesWithTimes peerFile jitter.dat jitter.pdf
mkdir peerFile
logFile=$1
cat $logFile |sort |grep "END_LOG"| awk '{print $3}' >leaves
cat $logFile |sort |grep "END_LOG"| awk '{print $3, $2}' >leavesWithTimes
for peerId  in `cat leaves`; do
  cat $logFile |sort | grep $peerId |awk '{print $2, $4}' |tail -2 | grep 'PeerPosition'>peerFile/$peerId
done
python createJitterDataset.py
gnuplot jitter.gp
