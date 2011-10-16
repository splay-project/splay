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
	db.do("DROP TABLE IF EXISTS splayds")
	db.do("DROP TABLE IF EXISTS splayd_availabilities")
	db.do("DROP TABLE IF EXISTS jobs")
	db.do("DROP TABLE IF EXISTS job_mandatory_splayds")
	db.do("DROP TABLE IF EXISTS splayd_jobs")
	db.do("DROP TABLE IF EXISTS splayd_selections")
	db.do("DROP TABLE IF EXISTS blacklist_hosts")
	db.do("DROP TABLE IF EXISTS actions")
	db.do("DROP TABLE IF EXISTS locks")
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

	db.do("CREATE TABLE IF NOT EXISTS jobs (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			ref VARCHAR(255) NOT NULL,
			user_id INT NOT NULL,
			created_at datetime default NULL,
                        scheduled_at datetime default NULL,
                        strict ENUM('TRUE','FALSE') DEFAULT 'FALSE',
			
			name VARCHAR(255),
			description VARCHAR(255),

			localization VARCHAR(2),
			distance INT,
			latitude DECIMAL(10,6),
			longitude DECIMAL(10,6),

			bits ENUM('32', '64') NOT NULL DEFAULT '32',
			endianness ENUM('little', 'big') NOT NULL DEFAULT 'little',
			max_mem INT NOT NULL DEFAULT '2097152',
			disk_max_size INT NOT NULL DEFAULT '67108864',
			disk_max_files INT NOT NULL DEFAULT '512',
			disk_max_file_descriptors INT NOT NULL DEFAULT '32',
			network_max_send BIGINT(14) NOT NULL DEFAULT '134217728',
			network_max_receive BIGINT(14) NOT NULL DEFAULT '134217728',
			network_max_sockets INT NOT NULL DEFAULT '32',
			network_nb_ports INT NOT NULL DEFAULT '1',
			network_send_speed INT NOT NULL DEFAULT '51200',
			network_receive_speed INT NOT NULL DEFAULT '51200',
			udp_drop_ratio DECIMAL(3, 2) NOT NULL DEFAULT '0',
			code TEXT NOT NULL,
			script TEXT NOT NULL,
			nb_splayds INT NOT NULL DEFAULT '1',
			factor DECIMAL(3, 2) NOT NULL DEFAULT '1.25',
			splayd_version VARCHAR(255),
			max_load DECIMAL(5,2) NOT NULL DEFAULT '999.99',
			min_uptime INT NOT NULL DEFAULT '0',
			hostmasks VARCHAR(255),
			max_time INT DEFAULT '10000',
			
			die_free ENUM('TRUE','FALSE') DEFAULT 'TRUE',
			keep_files ENUM('TRUE','FALSE') DEFAULT 'FALSE',

			scheduler ENUM('standard','trace') DEFAULT 'standard',
			scheduler_description TEXT,

			list_type ENUM('HEAD','RANDOM') DEFAULT 'HEAD',
			list_size INT NOT NULL DEFAULT '0',

			command VARCHAR(255),
			command_msg TEXT,

			status ENUM('LOCAL','REGISTERING','RUNNING', 'ENDED','NO_RESSOURCES','REGISTER_TIMEOUT','KILLED','QUEUED') DEFAULT 'LOCAL',
			status_time INT NOT NULL,
			status_msg TEXT,

			INDEX ref (ref)
			)")

	db.do("CREATE TABLE IF NOT EXISTS job_mandatory_splayds (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			job_id INT NOT NULL,
			splayd_id INT NOT NULL
			)")

	db.do("CREATE TABLE IF NOT EXISTS splayd_jobs (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			splayd_id INT NOT NULL,
			job_id INT NOT NULL,
			status ENUM('RESERVED','WAITING','RUNNING') DEFAULT 'RESERVED',
			INDEX splayd_id (splayd_id)
			)")

	db.do("CREATE TABLE IF NOT EXISTS splayd_selections (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			splayd_id INT NOT NULL,
			job_id INT NOT NULL,
			selected ENUM('TRUE','FALSE') DEFAULT 'FALSE',
			trace_number INT,
			trace_status ENUM('RUNNING', 'WAITING') DEFAULT 'WAITING',
			reset ENUM('TRUE','FALSE') DEFAULT 'FALSE',
			replied ENUM('TRUE','FALSE') DEFAULT 'FALSE',
			reply_time DECIMAL(8, 5) NULL,
			port INT NOT NULL,
			INDEX splayd_id (splayd_id),
			INDEX job_id (job_id)
			)")

	db.do("CREATE TABLE IF NOT EXISTS blacklist_hosts (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			host VARCHAR(255)
			)")

	db.do("CREATE TABLE IF NOT EXISTS actions (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			splayd_id INT NOT NULL,
			job_id INT NOT NULL,
			command VARCHAR(255),
			data TEXT,
			status ENUM('TEMP', 'WAITING', 'SENDING', 'FAILURE') DEFAULT 'WAITING',
			position INT,
			INDEX splayd_id (splayd_id),
			INDEX job_id (job_id)
			)")

	db.do("CREATE TABLE IF NOT EXISTS local_log (
			id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
			splayd_id INT NOT NULL,
			job_id INT NOT NULL,
			data TEXT,
			INDEX splayd_id (splayd_id),
			INDEX job_id (job_id)
			)")

	db.do("CREATE TABLE IF NOT EXISTS locks (
			id INT NOT NULL,
			job_reservation INT NOT NULL DEFAULT '0'
			) type=innodb")

	db.do("INSERT INTO locks SET
			id='1',
			job_reservation='0'")

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

end

db = DBUtils::get_new
drop_db(db)
init_db(db)
db.disconnect
