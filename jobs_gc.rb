#!/usr/bin/env ruby

## Splay Controller ### v1.0.7 ###
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


# GRANT ALL PRIVILEGES ON splay.* TO splay@localhost IDENTIFIED BY 'splay';

require 'lib/all'

def gc_jobs(db)
	db.do("DELETE FROM jobs WHERE created_at < NOW() - INTERVAL 1 WEEK;")
end

db = DBUtils::get_new
gc_jobs(db)
db.disconnect
