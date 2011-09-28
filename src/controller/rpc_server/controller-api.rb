#!/usr/bin/env ruby
## Splay Controller ### v1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splay.
## 
## Splayd is free software: you can redistribute it and/or modify 
## it under the terms of the GNU General Public License as published 
## by the Free Software Foundation, either version 3 of the License, 
## or (at your option) any later version.
## 
## Splayd is distributed in the hope that it will be useful,but 
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
## See the GNU General Public License for more details.
## 
## You should have received a copy of the GNU General Public License
## along with Splayd. If not, see <http://www.gnu.org/licenses/>.

require 'webrick'
$:.unshift( '../../../lib' )
require 'rubygems'
require 'orbjson'
include WEBrick


Socket.do_not_reverse_lookup = true

$logger = Logger.new( "orbjson.log" )
$logger.level = Logger::DEBUG

s = HTTPServer.new( :Port => 2222,
                    :DocumentRoot  =>  File.dirname( __FILE__ )  )

s.mount("/json-rpc", Orbjson::WEBrick_JSON_RPC )


# These mounts are a handy way to to kill a WEBrick instance via a URL call,
# useful mostly during debugging.  Probably less useful when you've deployed
# the applicaton.  Consider removing these before going live.
# s.mount_proc( "/exit" ){|req, res| s.shutdown;  exit;  } 
# s.mount_proc( "/quit" ){|req, res| s.shutdown;  exit; }   


# You can configure the Orbjsn services list in a few ways.
# Well, three, really:
#  1. Pass in a path to a local YAML file; the path must begin with
#   'file://'
#     For example: cfg = 'file://config.yaml'
#     Orbjson::System.init( cfg )
#     
#  2. Pass in some YAML:   
#    cfg = 'services/sample: 
#            - Details'
#    Orbjson::System.init( cfg )
#            
#  3. Pass in some an axtual Hash object: 
#    cfg = { 'services/sample' => ['Details'] }
#    Orbjson::System.init( cfg )
#
#  The hash (however you express it) consists of 'require' paths mapped
#  to arrays of classes to instantiate.


# Change this to suit your actual situation: If you use a configuration file,
# # make sure you have the correct name, path, and contents.
# This example expects to find the file 'config.yml' in the same dir
# as server.rb 
cfg = { 'controller-api' => ['Ctrl_api'] }
#cfg = "file://config.yml"

Orbjson::System.init( cfg )


trap( "INT" ){ s.shutdown }
trap( 1 ){ s.shutdown }
s.start

