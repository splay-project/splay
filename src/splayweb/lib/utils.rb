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

# MySQL escaping
# TODO NUL byte
def addslashes(str)
	if not str
		return ''
	else
		return str.to_s.gsub(/\\/, "\\\\\\").gsub(/'/, "\\\\'").gsub(/"/, "\\\"")
	end
end

def is_bytecode(lines)
	if raw_code[0,4] =~ /\x1BLua/
		return true
	else
		return false
	end
end
		
def parse_ressources(lines)
	settings = false
	options = {}
	# die_free is set by scheduler trace, but it's not an user settable setting
	accepted = [
		"localization", "distance", "latitude", "longitude",
		"bits", "endianness", "max_mem", "disk_max_size", "disk_max_files",
		"disk_max_file_descriptors", "network_max_send", "network_max_receive",
		"network_max_sockets", "network_nb_ports", "network_send_speed",
		"network_receive_speed", "nb_splayds", "factor",
		"splayd_version", "max_load", "min_uptime", "hostmasks",
		"max_time", "scheduler", "list_type", "strict", "scheduled_at", "list_size", "keep_files"]

	lines.each do |line|
		if not settings
			if line =~ /.*BEGIN SPLAY RESSOURCES RESERVATION.*/
				settings = true
			end
		else
			if line =~ /.*END SPLAY RESSOURCES RESERVATION.*/
				settings = false
			else
				vals = line.split(" ")
				if vals.size == 2
					if accepted.include?(vals[0])
						options[vals[0]] = vals[1]
					else
						puts "Not accepted option: #{vals[0]}"
					end
				end
			end
		end
	end
	return options
end

def to_sql(options)
	s = ""
	options.each do |var, val|
		s += ", #{var}='#{addslashes(val.to_s)}'"
	end
	return s
end

def to_human(options)
	s = ""
	options.each do |var, val|
		s += "#{var}\t#{val}\n"
	end
	return s
end

def parse_trace(lines)
	trace = ""
	settings = false
	lines.each do |line|
		if not settings
			if line =~ /.*BEGIN SPLAY TRACE.*/
				settings = true
			end
		else
			if line =~ /.*END SPLAY TRACE.*/
				settings = false
			else
				trace += line
			end
		end
	end
	return trace[0, trace.size - 1]
end

def clean_source(lines)
	if lines[0]  =~ /^#!.*/
		lines.delete_at(0)
	end
	return lines
end

def only_code(lines)
	if lines[0] =~ /^#!.*/
		lines.delete_at(0)
	end
	code = ""
	settings = false
	lines.each do |line|
		if not settings
			if line =~ /.*BEGIN SPLAY TRACE.*/ or
					line =~ /.*BEGIN SPLAY RESSOURCES RESERVATION.*/
				settings = true
			else
				code += line
			end
		else
			if line =~ /.*END SPLAY TRACE.*/ or
					line =~ /.*END SPLAY RESSOURCES RESERVATION.*/
				settings = false
			end
		end
	end
	return code
end

def watch(job)
	j = {}
	j['status'] = "LOCAL"
	old_status = "LOCAL"
	while j['status'] != "ENDED" and
		j['status'] != "NO_RESSOURCES" and
		j['status'] != "REGISTER_TIMEOUT" and
		j['status'] != "KILLED" and
		j['status'] != "RUNNING"

		sleep(1)
		j = $db.select_one "SELECT * FROM jobs WHERE ref='#{job['ref']}'"
		if j['status'] != old_status
			puts j['status']
			if j['status'] == "RUNNING"
				$db.select_all "SELECT * FROM splayd_selections WHERE job_id='#{j['id']}'
						AND selected='TRUE'" do |ms|
					m = $db.select_one "SELECT * FROM splayds WHERE id='#{ms['splayd_id']}'"
					if j['network_nb_ports'] > 0
						puts "    #{m['id']} #{m['name']} #{m['ip']} #{ms['port']} - #{ms['port'] +
								j['network_nb_ports'] - 1}"
					else
						puts "    #{m['id']} #{m['name']} #{m['ip']} no ports"
					end
				end
			end
			if j['status'] == "NO_RESSOURCES"
				puts j['status_msg']
			end
			puts "Task  ID: #{job['id']}  REF: #{job['ref']}"
			puts
		end
		old_status = j['status']
	end
	puts job['id']
end

def command_line_to_code(file_name, arg_pos)
	code = "arg = {}\narg[0] = '#{file_name}'\n"
	lua_pos = 0
	while true
		if not ARGV[arg_pos] then break end
		code += "arg[#{lua_pos += 1}] =  '#{ARGV[arg_pos]}'\n"
		arg_pos += 1
	end
	return code
end
