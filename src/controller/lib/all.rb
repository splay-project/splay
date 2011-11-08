## Splay Controller ### v1.2 ###
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

require "#{dir}/common"

require "#{dir}/splayd"
require "#{dir}/logd"
require "#{dir}/jobd"
require "#{dir}/jobd_standard"
require "#{dir}/jobd_trace"
require "#{dir}/jobd_trace_alt"
require "#{dir}/unseend"
require "#{dir}/statusd"
require "#{dir}/blacklistd"
require "#{dir}/loadavgd"

$db = DBUtils.get_new
$dbt = DBUtils.get_new

