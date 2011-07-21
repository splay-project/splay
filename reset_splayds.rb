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

def drop_db(db)
	db.do("DROP TABLE IF EXISTS splayds")
	db.do("DROP TABLE IF EXISTS splayd_availabilities")
end

def init_db(db)
	db.do("CREATE TABLE IF NOT EXISTS splayds (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,

			`key` VARCHAR(255) NOT NULL,
			ip VARCHAR(255),
			hostname VARCHAR(255),
			session VARCHAR(255),
			name VARCHAR(255),

			country VARCHAR(2),
			city VARCHAR(255),
			latitude DECIMAL(10,6),
			longitude DECIMAL(10,6),

			version VARCHAR(255),
			lua_version VARCHAR(255),
			bits ENUM('32', '64') DEFAULT '32',
			endianness ENUM('big', 'little') DEFAULT 'little',
			os VARCHAR(255),
			full_os VARCHAR(255),
			start_time INT,

			load_1 DECIMAL(5,2) DEFAULT '999.99',
			load_5 DECIMAL(5,2) DEFAULT '999.99',
			load_15 DECIMAL(5,2) DEFAULT '999.99',

			max_number INT,
			max_mem INT,
			disk_max_size INT,
			disk_max_files INT,
			disk_max_file_descriptors INT,
			network_max_send BIGINT(14),
			network_max_receive BIGINT(14),
			network_max_sockets INT,
			network_max_ports INT,
			network_send_speed INT,
			network_receive_speed INT,
			command ENUM('DELETE'),

			status ENUM('REGISTERED','PREAVAILABLE','AVAILABLE','UNAVAILABLE','RESET','DELETED') DEFAULT 'REGISTERED',
			last_contact_time INT,
			INDEX ip (ip),
			INDEX `key` (`key`)
			) type=innodb")

	db.do("CREATE TABLE IF NOT EXISTS splayd_availabilities (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			splayd_id INT NOT NULL,
			ip VARCHAR(255),
			status ENUM('AVAILABLE','UNAVAILABLE','RESET') DEFAULT 'AVAILABLE',
			time INT NOT NULL
			)")
end

db = DBUtils::get_new
drop_db(db)
init_db(db)
db.disconnect
