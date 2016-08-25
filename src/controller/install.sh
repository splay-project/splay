#!/bin/bash - 
#===============================================================================
#
#          FILE: install.sh
# 
#         USAGE: ./install.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (RCG), raziel.carvajal@unine.ch
#  ORGANIZATION: 
#       CREATED: 08/25/2016 17:16
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error


sudo apt-get install ruby mysql-server ruby2.3-dev libmysqld-dev

sudo gem install openssl dbd-mysql mysql dbi net-ping nokogiri algorithms sequel

echo "Database initialization with mysql, please provide your root password..."
mysql -u root -p < init.mysql

echo -e "DONE\nCreation of Splay tables..."
./init_db.rb
./init_users.rb
