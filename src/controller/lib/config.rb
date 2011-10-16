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


class SplayControllerConfig
	CTLVersion = 1.11

	SQL_TYPE = DBConfig::SQL_TYPE
	SQL_DB =  DBConfig::SQL_DB
	SQL_HOST = DBConfig::SQL_HOST
	SQL_USER = DBConfig::SQL_USER
	SQL_PASS = DBConfig::SQL_PASS

	SSL = true
	Production = false # Put true in prod, remove some tests to permit local testing.
	AutoAddSplayds = true # In production must be false

	# Permit to detect when a node is comming from a NAT gateway and restore his
	# true IP (from the key in format: "NAT_ip"). Then, nodes from external need
	# to change internal IP by gateway IP and using the same port. That solution
	# need a port mapping between gateway and each internal IPs.
	NATGatewayIP = nil

	LogdIP = nil # nil => controller's ip
	LogMaxSize = 32 * 1024 # 32 ko of logs for each nodes.
	LogDir = "#{Dir.pwd}/logs"
	# links/job_key.txt => logs/job_id
	LinkLogDir = "#{Dir.pwd}/links"
	LogdPort = 11100 # base port (first port if more than one splayd)

	SplaydPort = 11000 # base port (first port if more than one splayd)

	PublicIP = nil # To set ourself in the blacklist

	NumSplayd = 10
	NumLogd = 10

	# Enable geolocalization from an external module (not installed by default)
	Localize = false

	# SplaydProtocol
	SPSleepTime = 1
	SPPingInterval = 60
	SPSocketTimeout = 60

	LoadavgInterval = 300 # should be 60, but better when async protocol
	StatusInterval = 60
	BlacklistInterval = 120
	UnseenInterval = 60

	# Jobd
	RegisterTimeout = 30
	JobPollTime = 1
end
