#!/bin/bash - 
#===============================================================================
#
#          FILE: deploy_controller.sh
# 
#         USAGE: ./deploy_controller.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (), raziel.carvajal@uclouvain.be
#  ORGANIZATION: 
#       CREATED: 06/21/2018 15:24
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

cd splay-CONTROLLER_1.07
ruby -rubygems init_db.rb
ruby -rubygems init_users.rb
ruby -rubygems controller.rb
