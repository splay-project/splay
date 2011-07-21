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


require '../lib/common'

$log.level = Logger::INFO
	
if ARGV.size < 2
	puts("arguments: <splayd_id> <job_id>")
	exit
end

splayd_id = ARGV[0].to_i
jobd_id = ARGV[1].to_i

# TODO check if the request is already queued and in that case do not send it
# again
$db.do "INSERT INTO actions SET
		splayd_id='#{splayd_id}',
		jobd_id='#{jobd_id}',
		command='LOCAL_LOG'"

# TODO finish, watch in local_log db
#
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
