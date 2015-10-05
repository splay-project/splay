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

require File.expand_path(File.join(dir, 'common'))

require File.expand_path(File.join(dir, 'splayd_server'))
require File.expand_path(File.join(dir, 'logd'))
require File.expand_path(File.join(dir, 'jobd'))
require File.expand_path(File.join(dir, 'jobd_standard'))
require File.expand_path(File.join(dir, 'jobd_trace'))
require File.expand_path(File.join(dir, 'jobd_grid'))
require File.expand_path(File.join(dir, 'jobd_trace_alt'))
require File.expand_path(File.join(dir, 'unseend'))
require File.expand_path(File.join(dir, 'statusd'))
require File.expand_path(File.join(dir, 'blacklistd'))
require File.expand_path(File.join(dir, 'loadavgd'))

$db = DBUtils.get_new_mysql_sequel
$dbt = DBUtils.get_new_mysql_sequel

