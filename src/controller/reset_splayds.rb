#!/usr/bin/env ruby

#Drop the splayds table from the splay database: useful to reinitialize 
#a cluster without shutting down the controller.

require File.expand_path(File.join(File.dirname(__FILE__), 'lib/all'))

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

if __FILE__ == $0
  db = DBUtils::get_new_mysql_sequel
  drop_db(db)
  init_db(db)
  db.disconnect
end
