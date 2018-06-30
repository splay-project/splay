#!/bin/bash -
#===============================================================================
#
#          FILE: deploy_web_server.sh
#
#         USAGE: ./deploy_web_server.sh
#
#   DESCRIPTION:
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (), raziel.carvajal@uclouvain.be
#  ORGANIZATION:
#       CREATED: 06/21/2018 15:25
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

cd cli-server
ruby -rubygems cli-server.rb
