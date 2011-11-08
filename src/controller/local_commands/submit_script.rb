#!/usr/bin/env ruby

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


require '../lib/common'

$log.level = Logger::INFO
	
if ARGV.size < 2
	puts("arguments: <lua_file> <nb_splayds>")
	exit
end

# Lua file
file = ARGV[0]

puts "Reading file: #{file}\n"

script = File.readlines(file)

options = {}
if ARGV[1]
	options['nb_splayds'] = ARGV[1].to_i
end

ref = OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s)

$db.do "INSERT INTO jobs SET
		ref='#{ref}'
		#{to_sql(options)}
		, script='#{addslashes(script)}'"

job = $db.select_one "SELECT * FROM jobs WHERE ref='#{ref}'"

puts "Task transmitted to the controller: #{job['id']} (#{ref})"
puts
if options.size != 0 then puts(to_human(options)) end

watch(job)
