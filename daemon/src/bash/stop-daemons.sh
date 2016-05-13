#!/bin/bash - 
#===============================================================================
#
#          FILE: stop-daemons.sh
# 
#         USAGE: ./stop-daemons.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 05/13/2016 16:57
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
killall splayd
