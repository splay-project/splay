#!/usr/bin/env ruby

## Splay Controller ### v1.0.6 ###
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

title = <<END_OF_STRING
 ____        _                  _   _ 
/ ___| _ __ | | __ _ _   _  ___| |_| |
\\___ \\| '_ \\| |/ _` | | | |/ __| __| |
 ___) | |_) | | (_| | |_| | (__| |_| |
|____/| .__/|_|\\__,_|\\__, |\\___|\\__|_|
      |_|            |___/            

END_OF_STRING
puts title

while true
	outm = false
	puts "> Main Menu"
	puts "  m:splayds, j:jobs, b: blacklist, x:exit"
	puts
	menu = gets.chomp
	case menu
	when /m/ # splayds menu
		selected_splayd = nil
		while true
			out = false
			puts ">> Splayd Menu"
			puts "   m:select splayd, a:add, l:list, x:exit"
			if selected_splayd
				puts
				puts ">>>> For splayd: #{selected_splayd}"
				puts "       d:details, s:show nodes, k:kill, c:show actions, r:reset"
			end
			puts
			func = gets.chomp
			case func
			when /m/
				puts "Give splayd id or ref:"
				a = gets.chomp
				splayd = $db.select_one "SELECT id FROM splayds WHERE
						id='#{a}' OR ref='#{a}'"
				if splayd
					selected_splayd = splayd['id']
					puts "Selected splayd ID: #{selected_splayd}"
				else
					puts "Splayd not found."
				end
				puts
			when /a/
				puts "Give splayd ref:"
				ref = gets.chomp
				$db.do("INSERT INTO splayds SET ref='#{ref}'")
				puts "Splayd added."
				puts
			when /l/
				$db.select_all "SELECT * FROM splayds ORDER BY status, id" do |splayd|
					puts "ID: #{splayd['id']} - ref: #{splayd['ref']} - #{splayd['status']}"
				end
				puts
			when /s/
				if selected_splayd
					$db.select_all "SELECT * FROM splayd_jobs WHERE
							splayd_id='#{selected_splayd}'" do |ms|
						puts "Job ID: #{mm['job_id']} - status: #{mm['status']}"
					end
				else
					puts "Select a splayd first."
				end
				puts
			when /k/
				if selected_splayd
					$db.do "INSERT INTO actions SET
						  splayd_id='#{selected_splayd}',
						  command='KILL'"
					puts "Sended."
				else
					puts "Select a splayd first."
				end
				puts
			when /c/
				if selected_splayd
					$db.select_all "SELECT * FROM actions WHERE
							splayd_id='#{selected_splayd}'" do |action|
						puts "ID: #{action['id']} - cmd: #{action['command']}"
					end
				else
					puts "Select a splayd first."
				end
				puts
			when /d/
				if selected_splayd
					m = $db.select_one "SELECT * FROM splayds WHERE id='#{selected_splayd}'"
					
					puts "Splayd #{m['ref']} (#{m['id']})"
					puts "#{m['name']} - #{m['localization']}"
					puts "Host: #{m['os']}, #{m['bits']} bits, #{m['endianness']} endian"
					puts "IP: #{m['ip']} - #{m['status']}"
				else
					puts "Select a splayd first."
				end
				puts
			when /x/
				out = true
			end
			if out then break end
		end
	when /j/ # jobs menu
		selected_job = nil
		while true
			out = false
			puts ">> Job Menu"
			puts "   j:select job, a:add, l:list, g:logs, x:exit"
			if selected_job
				puts
				puts ">>>> For job: #{selected_job}"
				puts "       m:splayds, d:details, w:watch, k:kill"
			end

			puts
			func = gets.chomp
			case func
			when /j/
				puts "Give job id or ref:"
				a = gets.chomp
				job = $db.select_one "SELECT id FROM jobs WHERE
						id='#{a}' OR ref='#{a}'"
				if job
					selected_job = job['id']
					puts "Selected job ID: #{selected_job} - #{job['status']}"
				else
					puts "Job not found."
				end
				puts
			when /l/
				$db.select_all "SELECT * FROM jobs" do |job|
					puts "ID: #{job['id']} - ref: #{job['ref']} - #{job['status']}"
				end
				puts
			when /a/
				ref = OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s)
				puts "Job ref: #{ref}"
				puts "Enter file"
				file = gets.chomp
				count = 1
				File.open(file).each do |line|
					if not(count == 1 and line =~ /^#!.*/)
						code += line
					end
					count += 1
				end
				puts "Enter how many splayds do you want:"
				nb_splayds = get
				$db.do "INSERT INTO jobs SET
						ref='#{ref}',
						code='#{addslashes(code)}',
						nb_splayds='#{nb_splayds}'"
				puts "Job submitted"
				puts
			when /k/
				if selected_job
					$db.do "UPDATE jobs SET command='KILL' WHERE id='#{selected_job}'"
					puts "Job killed."
				else
					puts "Select a job first."
				end
			when /m/
				# TODO check the status, at the begining, job is given to more
				# splayds for the REGISTER part...
				if selected_job
					c_ended = 0
					c_running = 0
					$db.select_all "SELECT * FROM splayd_selections
							WHERE job_id='#{selected_job}' ORDER BY splayd_id" do |ms|

						m = $db.select_one "SELECT * FROM splayds WHERE id='#{ms['splayd_id']}'"
						s = $db.select_one "SELECT * FROM splayd_jobs
								WHERE job_id='#{selected_job}' AND
								splayd_id='#{ms['splayd_id']}' AND
								status!='RESERVED'"

						if s
							puts "#{m['id']} #{m['name']} [#{m['ip']} #{m['status']}] => RUNNING"
							c_running += 1
						else
							#puts "#{m['name']} [#{m['ip']} #{m['status']}] => ENDED"
							c_ended += 1
						end
					end
					puts "Job given to #{c_ended + c_running} splayds."
					if c_running > 0
						puts "Still running on #{c_running} splayds."
					end
				else
					puts "Select a job first."
				end

			when /w/
				# TODO
				j = {}
				j['status'] = "LOCAL"
				old_status = "LOCAL"
				while j['status'] != "ENDED" and j['status'] != "NO_RESSOURCES" and j['status'] != "REGISTER_TIMEOUT"
					j = $db.select_one "SELECT * FROM jobs WHERE ref='#{ref}'"
					if j['status'] != old_status
						puts j['status']
						if j['status'] == "NO_RESSOURCES"
							puts j['status_msg']
						end
					end
					old_status = j['status']
					sleep(1)
				end
			when /x/
				out = true
			end
			if out then break end
		end
	when /x/
		outm = true
	end
	if outm then break end
end
