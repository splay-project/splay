#!/bin/bash -
#===============================================================================
#
#          FILE: deploy.sh
#
#         USAGE: ./deploy.sh
#
#   DESCRIPTION:
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Raziel Carvajal-Gomez (), raziel.carvajal@uclouvain.be
#  ORGANIZATION:
#       CREATED: 06/21/2018 17:02
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error

LUA_PATH=$(lua -e 'print(package.path)')
LUA_PATH="${LUA_PATH};/usr/splay/lib/lua/?.lua"
LUA_CPATH=$(lua -e 'print(package.cpath)')
LUA_CPATH="${LUA_CPATH};/usr/splay/lib/c/?.so"

LUA_PATH=${LUA_PATH} LUA_CPATH=${LUA_CPATH} lua splayd.lua ${HOSTNAME} splay_controller 11000 11000 12000
