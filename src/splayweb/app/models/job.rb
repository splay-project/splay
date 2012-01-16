## Splayweb ### v1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splayd.
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


class Job < ActiveRecord::Base
	
	belongs_to :user
	has_many :splayd_selections
	has_many :splayds, :through => :splayd_selections

	validates_presence_of :bits, :endianness, :max_mem
	validates_presence_of :disk_max_size, :disk_max_files, :disk_max_file_descriptors
	validates_presence_of :network_max_send, :network_max_receive, :network_max_sockets
	validates_presence_of :network_nb_ports, :network_send_speed, :network_receive_speed
	validates_presence_of :code, :nb_splayds, :list_type, :strict, :list_size, :splayd_version

	validates_numericality_of :max_mem, :only_integer => true
	validates_numericality_of :disk_max_size, :disk_max_files, :disk_max_file_descriptors, :only_integer => true
	validates_numericality_of :network_max_send, :network_max_receive, :network_max_sockets, :only_integer => true
	validates_numericality_of :network_nb_ports, :network_send_speed, :network_receive_speed, :only_integer => true
	validates_numericality_of :nb_splayds, :list_size, :max_time, :min_uptime, :only_integer => true
	validates_numericality_of :max_load
end
