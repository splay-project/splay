## Splay Controller ### v1.3 ###
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


dir = File.dirname(__FILE__)

require 'logger' # Logger::Error
$log = Logger.new(STDERR)
#$log.level = Logger::DEBUG
$log.level = Logger::ERROR
$log.datetime_format = "%Y-%m-%d %H:%M:%S "

$bench = Logger.new(STDERR)
$bench.level = Logger::DEBUG
$bench.datetime_format = "%Y-%m-%d %H:%M:%S "

require 'socket' # SocketError and SystemCallError (Errno::*)
require 'timeout' # Timeout::Error
require 'openssl' # OpenSSL::OpenSSLError
# require 'rubygems'
# require 'fastthread'
require 'thread' # ThreadError
require 'fileutils'
require 'dbi' # DBI::Error
require 'resolv'

require File.expand_path(File.join(dir, 'db_config'))
require File.expand_path(File.join(dir, 'config'))
require File.expand_path(File.join(dir, 'log_object'))
require File.expand_path(File.join(dir, 'dbutils'))

require "json" #gem install json
require File.expand_path(File.join(dir, 'llenc'))
require File.expand_path(File.join(dir, 'array_rand'))
require File.expand_path(File.join(dir, 'utils'))
require File.expand_path(File.join(dir, 'distributed_lock'))

if SplayControllerConfig::Localize
  require File.expand_path(File.join(dir, 'localization'))
end

$db = DBUtils.get_new_mysql_sequel
# $new_db = DBUtils.get_new_mysql

BasicSocket.do_not_reverse_lookup = true
$DEBUG = false
$VERBOSE = false
OpenSSL::debug = false

if not SplayControllerConfig::PublicIP
	$log.warn("You must set your public ip in production mode.")
end
