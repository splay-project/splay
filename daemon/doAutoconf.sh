#!/bin/bash - 
#===============================================================================
#
#          FILE: doAutoconf.sh
# 
#         USAGE: ./doAutoconf.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 29/12/2015 17:18
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
aclocal
autoheader
autoconf
automake --add-missing
./configure
make dist
