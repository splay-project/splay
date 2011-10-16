#!/usr/bin/env ruby

## Splay Controller ### v1.1.1 ###
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

def drop_db(db)
	db.do("DROP TABLE IF EXISTS users")
end

def init_db(db)
	db.do("CREATE TABLE IF NOT EXISTS users (
		id int(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
		login varchar(255) default NULL,
		email varchar(255) default NULL,
		crypted_password varchar(40) default NULL,
		salt varchar(40) default NULL,
		created_at datetime default NULL,
		updated_at datetime default NULL,
		remember_token varchar(255) default NULL,
		remember_token_expires_at datetime default NULL,
		admin int(11) default '0',
		demo int(11) default '1'
		);")
	time_now = Time.new().strftime("%Y-%m-%d %T")
	$db.do("INSERT INTO users SET 
		login='admin', 
		crypted_password='d033e22ae348aeb5660fc2140aec35850c4da997', 
		created_at='#{time_now}', 
		admin=1, 
		demo=0")

end

db = DBUtils::get_new
drop_db(db)
init_db(db)
db.disconnect
