#!/bin/bash - 
#===============================================================================
#
#          FILE: launch_controller.sh
# 
#         USAGE: ./launch_controller.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 08/26/2016 14:13
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
echo -e "Launching controller...\n"
./controller.rb &> ControllerRb.log &
pid=$!
echo -e "\tController PID: $pid\nLaunching server to answer job sumbitions..."
cd cli-server
./cli-server.rb &> CliServerRb.log &
pid=$!
echo -e "\tCli-Server PID: $pid\nController's process were launched"
