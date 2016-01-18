#!/bin/bash - 
#===============================================================================
#
#          FILE: clean.sh
# 
#         USAGE: ./clean.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 29/12/2015 17:15
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
rm -fr config.* stamp-h1 Makefile configure Makefile.in autom4te.cache/
rm -fr aclocal.m4 depcomp compile install-sh missing 
here=`pwd`
rm -fr src/c/splayd src/c/jobd
for subDir in src/c src/c/lbase64 src/c/lua-cjson src/c/luacrypto ; do
  cd $subDir
  rm -fr Makefile Makefile.in .deps/ *.o *.so
  cd $here
done
cd etc/openssl-cert
rm -fr Makefile Makefile.in *.pem *.srl
