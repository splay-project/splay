## Splay Controller ### v1.3 ###
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

# JSON-RPC over HTTP client for SPLAY controller in Ruby - server side
# Created by José Valerio
#
# based on tutorial for Orbjson:
# http://orbjson.rubyforge.org/tutorial/getting_started_with_orbjson_short_version.pdf
# http://orbjson.rubyforge.org/tutorial/tutorial_code.tgz

require File.expand_path(File.join(File.dirname(__FILE__), '../lib/common'))
#require '../lib/common.rb'
#library required for hashing
require 'digest/sha1'
#Main class
class Ctrl_api
	#function get_log: triggered when a "GET LOG" message is received, returns the corresponding log file as a string
	def get_log(job_id, session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID
		#is valid)
		if (user) then
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']
			#if the user is admin (can see all the jobs) or the job belongs to her
			if (($db.select_one("SELECT * FROM jobs WHERE id=#{job_id}") and (user['admin'] == 1)) or ($db.select_one("SELECT * FROM jobs WHERE id=#{job_id} AND user_id=#{user_id}"))) then
				#opens the log file of the requested job
				log_file = File.open("../logs/"+job_id)
				#ok is true
				ret['ok'] = true
				#log is a string containing the log file
				ret['log'] = log_file.read
				#closes the file
				log_file.close
				#returns ret
				return ret
			end
			#if the 'if (user)' statement was true, the function would have ended with the return on the line above,
			#if not, the following lines are processed
			#ok is false
			ret['ok'] = false
			if user['admin'] == 1 then
				ret['error'] = "Job does not exist"
			else
				#error says that the job doesn't exist
				ret['error'] = "Job does not exist for this user"
			end
			#returns ret
			return ret
		end
		#if session ID was not valid, ok is false
		ret['ok'] = false
		#error says that the session ID was invalid
		ret['error'] = "Invalid or expired Session ID"
		#returns ret
		return ret
	end

	#function get_job_code: triggered when a "GET JOB CODE" message is received, returns the corresponding
	#source code as a string
	def get_job_code(job_id, session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID is valid)
		if (user) then
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']
			#job is the record that matches the job_id
			job = $db.select_one("SELECT * FROM jobs WHERE id=#{job_id}")
			#if job exists
			if job then
				#if the user is admin (can see all the jobs) or the job belongs to her
				if ((user['admin'] == 1) or (job['user_id'] == user_id)) then
					#ok is true
					ret['ok'] = true
					#code is a string containing the code
					ret['code'] = job['code']
					#returns ret
					return ret
				end
			end
			#if the 'if (user)' statement was true, the function would have ended with the return on the line above,
			# if not, the following lines are processed
			#ok is false
			ret['ok'] = false
			#error says that the job doesn't exist
			if user['admin'] == 1 then
				ret['error'] = "Job does not exist"
			else
				#error says that the job doesn't exist
				ret['error'] = "Job does not exist for this user"
			end
			#returns ret
			return ret
		end
		#if session ID was not valid, ok is false
		ret['ok'] = false
		#error says that the session ID was invalid
		ret['error'] = "Invalid or expired Session ID"
		#returns ret
		return ret
	end

	#function kill_job: triggered when a "KILL JOB" message is received, sends a KILL command to a job
	def kill_job(job_id, session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID is valid)
		if (user) then
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']
			#if the user is admin (can see all the jobs) or the job belongs to her
			if ((user['admin'] == 1) or ($db.select_one("SELECT * FROM jobs WHERE id=#{job_id} AND user_id=#{user_id}"))) then
				#writes KILL in the field 'command' of table 'jobs'; the contoller takes this command as an order
				#to kill the job
				$db.do("UPDATE jobs SET command='KILL' WHERE id='#{job_id}'")
				#ok is true
				ret['ok'] = true
				#returns ret
				return ret
			end
			#if the user is not admin and the job doesn't belong to her, ok is false
			ret['ok'] = false
			#error says that the job doesn't exist for the given user (if user is admin, the job doesn't exist at all)
			if user['admin'] == 1 then
				ret['error'] = "Job does not exist"
			else
				#error says that the job doesn't exist
				ret['error'] = "Job does not exist for this user"
			end
		end
		#if the session was not valid, ok is false
		ret['ok'] = false
		#error says that the session was not valid
		ret['error'] = "Invalid or expired Session ID"
		#returns ret
		return ret
	end
if SplayControllerConfig::AllowNativeLibs
	#When submitting a lib we test if it already exists in the DB.
	def pre_submit_lib(lib_filename, lib_sha1, lib_version, session_id)
		ret = Hash.new
		user = check_session_id(session_id)
		if user then 
		existing_lib = $db.select_one("SELECT * FROM libs WHERE lib_name='#{lib_filename}' AND lib_version='#{lib_version}' AND lib_sha1='#{lib_sha1}'")
		if existing_lib then
			ret['ok'] = true
			ret['message'] = "lib in db no need to upload"
		else
			ret['ok'] = true
			ret['message'] = "UPLOAD"
		end
		else
			ret['ok'] = false 
			ret['error'] = "Invalid or expired Session ID" 
		end
		return ret
	end
	
	#def submit_lib(lib_name, lib_version, lib_os, lib_arch, lib_sha1, lib_code, session_id)
	def submit_lib(lib_name, lib_version, lib_os, lib_arch, lib_sha1, lib_code, session_id, admin_username, admin_hashedpassword)
	 
	#if we are here there is no lib with the given hash, but there might be one that we want to update with the same name.
		
		ret = Hash.new
		#puts "writing lib : #{lib_name}, V= #{lib_version}, os=#{lib_os}, arch=#{lib_arch}"
		admin = $db.select_one("SELECT * FROM users WHERE login='#{admin_username}'")
		if admin then
			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
				existing_lib = $db.select_one("SELECT * FROM libs WHERE lib_name='#{lib_name}' AND lib_os='#{lib_os}' AND lib_arch='#{lib_arch}'")
				if existing_lib then
					$db.do("UPDATE libs SET lib_version='#{lib_version}', lib_sha1='#{lib_sha1}', lib_blob='#{addslashes(lib_code)}' WHERE id='#{existing_lib['id']}'")
					ret['ok'] = true
					ret['message'] = "EXISTING NATIVE LIBRARY UPDATED"
				else
					$db.do("INSERT INTO libs SET lib_name='#{lib_name}', lib_version='#{lib_version}', lib_os='#{lib_os}', lib_arch='#{lib_arch}', lib_sha1='#{lib_sha1}', lib_blob='#{addslashes(lib_code)}'")
					ret['ok'] = true
					ret['message'] = "NEW NATIVE LIBRARY INSTALLED"
					ret['os'] = lib_os  
				end
			end
		else
			ret['ok'] = false
			ret['error'] = "Not authenticated as admin"  
		end
		return ret
	end
	
	# Before writing the job in the DB we check that the required dep are met.
	def test_lib_exists(lib_filename, lib_version, session_id)
		ret = Hash.new
		user = check_session_id(session_id)
		if user then
		# TODO parse a string to determine the range of versions the users provides as compatibles
			a_lib = $db.select_one("SELECT * FROM libs WHERE lib_name='#{lib_filename}' AND lib_version='#{lib_version}'")
			if a_lib then
				ret['ok'] = true
				ret['message'] = 'lib exists'
			else
				ret['ok'] = false
				ret['error'] = "no such version "
			end
		else
			ret['ok'] = false
			ret['error'] = "Invalid or expired Session ID"
		end
		return ret
	end
	
	def list_libs(lib_name, session_id)
		ret = Hash.new
		user = check_session_id(session_id)
		if user then
			libs_list = Array.new
			if lib_name and lib_name != "" then
			#TODO give a detailed presentation of the libs, and possibly the splayds they are deployed on
				$db.select_all("SELECT * FROM libs WHERE lib_name='#{lib_name}'") do |a_lib|
				lib = Hash.new
				lib['lib_name'] = a_lib['lib_name']
				lib['lib_version'] = a_lib['lib_version']
				lib['lib_os'] = a_lib['lib_os']
				lib['lib_arch'] = a_lib['lib_arch'] 
				lib['lib_sha1'] = a_lib['lib_sha1']  
				libs_list.push(lib)
			end
		else
		#list all libs in db
			$db.select_all("SELECT * FROM libs") do |a_lib|
				lib = Hash.new
				lib['lib_name'] = a_lib['lib_name']
				lib['lib_version'] = a_lib['lib_version']
				lib['lib_os'] = a_lib['lib_os']
				lib['lib_arch'] = a_lib['lib_arch']   
				lib['lib_sha1'] = a_lib['lib_sha1']
				libs_list.push(lib)
			end
		end
			ret['ok'] = true
			ret['libs_list'] = libs_list
		else
			ret['ok'] = false
			ret['error'] = "Invalid or expired Session ID"
   		end
		return ret
	end

	def remove_lib(lib_name, lib_version, lib_arch, lib_os, lib_sha1, session_id, admin_username, admin_hashedpassword)
		ret = Hash.new
		user = check_session_id(session_id)
		admin = $db.select_one("SELECT * FROM users WHERE login='#{admin_username}'")
		if admin then
			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
				if lib_name and lib_name != ""
					where_clause = "WHERE lib_name='#{lib_name}' "
					if lib_version and lib_version != ""
	 						where_clause += "AND lib_version='#{lib_version}'"
					end
					if lib_arch and lib_arch != ""
						where_clause += "AND lib_arch='#{lib_arch}'"
				    end
					if lib_os and lib_os != ""
						where_clause += "AND lib_os='#{lib_os}'"
					end
					if lib_sha1 and lib_sha1 != ""
						where_clause += "AND lib_sha1='#{lib_sha1}'"
					end
					#puts where_clause
					$db.do("DELETE FROM libs #{where_clause}")
					ret['ok'] = true
					ret['message'] = "Lib deleted"
				else
					ret['ok'] = false
					ret['error'] = "Cannot use an empty string for lib_name"
				end
			end
		else
			ret['ok'] = false
			ret['error'] = "Not authenticated as admin"
		end
		return ret
	end
end
	#function submit_job: triggered when a "SUBMIT JOB" message is received, submits a job to the controller
	def submit_job(name, description, code, lib_filename, lib_version, nb_splayds, churn_trace, options, session_id, scheduled_at, strict, trace_alt, queue_timeout, multiple_code_files, designated_splayds_string, splayds_as_job,  topology)
	 	ret = Hash.new
		
		if  !SplayControllerConfig::AllowNativeLibs and lib_filename !=""
		 	ret['ok'] = false
  			ret['error'] = "Submitting jobs for native libs forbidden"
  			return ret
	  	end
		#checks the validity of the session ID
		user = check_session_id(session_id)
	  #when the sesion is valid
		if user then
      ref = OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s)
      user_id = user['id']
			time_now = Time.new().strftime("%Y-%m-%d %T")
       
			if options.class == Array then
				options = Hash.new
			end
			options[:ref]="#{ref}"
      options[:user_id]=user_id
      options[:created_at]="#{time_now}"
       
			if nb_splayds then
				if (nb_splayds>0) then
					options[:nb_splayds] = nb_splayds
				end
			end
      
      options[:description] = description or ""
    
      options[:name] = name or ""
		
			# scheduled job
			if scheduled_at && (scheduled_at > 0) then
				time_scheduled = Time.at(scheduled_at).strftime("%Y-%m-%d %T")
				options[:scheduled_at] = time_scheduled
			end
      
			# strict job
			if strict == "TRUE" then
				options[:strict] = strict
			end
      
			if churn_trace == "" then
				churn_field = ""  
        #options[:churn]      
			else
				options[:nb_splayds] = churn_trace.lines.count
				if trace_alt == "TRUE" then
					options[:scheduler] = 'tracealt'
				else
					options[:scheduler] = 'trace'
				end
        options[:die_free]='FALSE'
        options[:scheduler_description] = "#{addslashes(churn_trace)}"

			end

			if lib_filename != "" then
				options[:scheduler] = 'grid'
        options[:lib_name]="#{lib_filename}"
        options[:lib_version]="#{lib_version}"
			end

			if queue_timeout then
				options[:queue_timeout] = queue_timeout
 			end

			#multifile job
      if multiple_code_files == true then
				options[:multifile] = multiple_code_files
				code, ret = LuaMerger.new.merge_lua_files(code, ret)
				if code == "" then
					return ret
				end
			end
      options[:code]="#{addslashes(code)}"
      
      options[:topology]="#{topology}"
     
      job_inserted = $db[:jobs].insert(options)
      raise "Job not inserted" unless job_inserted
      
			#designated splayds
			if designated_splayds_string != "" then
				#eliminate white spaces
				job_id = $db.fetch("SELECT id FROM jobs WHERE ref='#{ref}'")
				designated_splayds_string.delete(' ')
				#prepare query
				q_jds = ""
				designated_splayds_string.split(',').each { |splayd_id|
					q_jds = q_jds + "('#{job_id}','#{splayd_id}'),"
				}
				q_jds = q_jds[0, q_jds.length - 1]
				$db.do("INSERT INTO job_designated_splayds (job_id, splayd_id) VALUES #{q_jds}")
			end

			#use the same splayds as another job
			if splayds_as_job != "" then
				job_id = $db.fetch("SELECT id FROM jobs WHERE ref='#{ref}'")
				other_job_id = splayds_as_job

				# check if the other job 
				# 1. was killed before execution (and splayds booking)
				# 2. is currently queued 
				# 3. it was rejected because of the lack of resources 
				other_job_splayds = $db.fetch("SELECT * FROM splayd_selections WHERE job_id='#{other_job_id}' AND selected='TRUE'")
				other_job_status = $db.fetch("SELECT status FROM jobs WHERE id='#{other_job_id}' AND (status='KILLED' OR status='QUEUED' OR status='NO_RESSOURCES')")

				if (other_job_status != nil && other_job_splayds == nil) then
					$db.do "INSERT INTO job_designated_splayds (job_id,other_job_status) VALUES ('#{job_id}','#{other_job_status}')"
				else
					# find the number of splayds used by the other job
					other_job_nb_splayds = $db.fetch("SELECT nb_splayds FROM jobs WHERE id='#{other_job_id}'")
					$db.do "UPDATE jobs SET nb_splayds='#{other_job_nb_splayds}' WHERE id='#{job_id}'"

					# find the splayds used by the other job
					q_jds = ""
					$db.fetch "SELECT * FROM splayd_selections
							WHERE job_id='#{other_job_id}' AND selected='TRUE'" do |jds|
						q_jds = q_jds + "('#{job_id}','#{jds['splayd_id']}'),"
					end
					q_jds = q_jds[0, q_jds.length - 1]
					$db.do "INSERT INTO job_designated_splayds (job_id,splayd_id) VALUES #{q_jds}"
				end
			end

			timeout = 30
      job = $db[:jobs].where('ref=?',ref)
			while timeout > 0
				sleep(1)
				timeout = timeout - 1
       
				job_status = job.get(:status)
        if job_status == "RUNNING" then
					ret['ok'] = true
					ret['job_id'] = job.get(:id) 
					ret['ref'] = ref
					return ret
				end
				if job_status == "NO_RESSOURCES" then
					ret['ok'] = false
					ret['error'] = "JOB " + job.get(:id).to_s + ": " + job['status_msg']
					return ret
				end
				#queued job behavior
				if job_status == "QUEUED" then
					ret['ok'] = true
					ret['job_id'] = job.get(:id)
					ret['ref'] = ref
					return ret
				end
			end
			#if timeout reached 0, ok is false
			ret['ok'] = false
			#error says that a timeout occured and suggests to check if the controller is running
			ret['error'] = "JOB " + job.get(:id).to_s + ": timeout; please check if controller is running"
			#returns ret
			return ret
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return ret
	end

	#function get_job_details: triggered when a "GET JOB DETAILS" message is received, returns the description, status and
	#host list of the job
	def get_job_details(job_id, session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID is valid)
		if (user) then
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']
			#if the user is admin (can see all the jobs) or the job belongs to her
			if ((user['admin'] == 1) or ($db.select_one("SELECT * FROM jobs WHERE id=#{job_id} AND user_id=#{user_id}"))) then
				host_list = Array.new
				$db.select_all("SELECT * FROM splayd_selections WHERE job_id='#{job_id}' AND selected='TRUE'") do |ms|
					m = $db.select_one("SELECT * FROM splayds WHERE id='#{ms['splayd_id']}'")
					host = Hash.new
					host['splayd_id'] = ms['splayd_id']
					host['ip'] = m['ip']
					host['port'] = ms['port']
					host_list.push(host)
				end
				job = $db.select_one("SELECT * FROM jobs WHERE id=#{job_id}")
				ret['ok'] = true
				ret['host_list'] = host_list
				ret['status'] = job['status']
				ret['ref'] = job['ref']
				ret['name'] = job['name']
				ret['description'] = job['description']
				if (user['admin'] == 1) then
					ret['user_id'] = job['user_id']
				end
				return ret
			end
			ret['ok'] = false
			if user['admin'] == 1 then
				ret['error'] = "Job does not exist"
			else
				#error says that the job doesn't exist
				ret['error'] = "Job does not exist for this user"
			end
			return ret
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return ret
	end

	#function list_jobs: triggered when a "LIS JOBS" message is received, returns the list of jobs that belong to
	#this user (all if user is admin.)
	def list_jobs(session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID is valid)
		if (user) then
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']
			job_list = Array.new
			if (user['admin'] == 1) then
				$db[:jobs].each do |ms|
					job = Hash.new
					job['id'] = ms['id']
					job['status'] = ms['status']
					job['user_id'] = ms['user_id']
					job_list.push(job)
				end
			else
				$db[:jobs].where('user_id=?',user_id) do |ms| 
					job = Hash.new
					job['id'] = ms['id']
					job['status'] = ms['status']
					job_list.push(job)
				end
			end
			ret['ok'] = true
			ret['job_list'] = job_list
			return ret
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return ret
	end

	#function list_splayds: triggered when a "LIST SPLAYDS" message is received, returns a list of all registered
	#splayds, containing splayd ID, IP address, key and current status
	def list_splayds(session_id)
		#initializes the return variable
		ret = Hash.new
		if (check_session_id(session_id)) then
			splayd_list = Array.new
			$db.select_all("SELECT * FROM splayds") do |ms|
				splayd=Hash.new
				splayd['splayd_id']=ms['id']
				splayd['ip']=ms['ip']
				splayd['status']=ms['status']
				splayd['key']=ms['key']
				splayd_list.push(splayd)
			end
			ret['ok'] = true
			ret['splayd_list'] = splayd_list
			return ret
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return ret
	end

	#function start_session: triggered when a "START SESSION" message is received, triggers the granting of a token or session
	#ID valid for 24h, and returns this token along with the expiry date
	def start_session(username, hashed_password)
  	#initializes the return variable
		ret = Hash.new
    user = $db[:users].where(' login = ? ',username)
		#user =#"SELECT * FROM users WHERE login='#{username}'"
		if user!=nil then
			hashed_password_from_db = user.get(:crypted_password)
      
			if (hashed_password == hashed_password_from_db) then
				time_tomorrow = Time.new + 3600*24
				remember_token_expires_at = time_tomorrow.strftime("%Y-%m-%d %T")
				remember_token = Digest::SHA1.hexdigest("#{username}--#{remember_token_expires_at}")
				$db.do("UPDATE users SET remember_token='#{remember_token}', remember_token_expires_at='#{remember_token_expires_at}' WHERE login='#{username}'")
				ret['ok'] = true
				ret['session_id'] = remember_token
				ret['expires_at'] = remember_token_expires_at
				return ret
			end
		end
		ret['ok'] = false
		ret['error'] = "Not authenticated"
		return ret
	end

	#function new_user: triggered when a "NEW USER" message is received, creates a new regular user
	def new_user(username, hashed_password, admin_username, admin_hashedpassword)
		#initializes the return variable
		ret = Hash.new
		admin = $db.select_one("SELECT * FROM users WHERE login='#{admin_username}'")
		if admin then
			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
				if not ($db.select_one("SELECT * FROM users WHERE login='#{username}'")) then
					time_now = Time.new().strftime("%Y-%m-%d %T")
					$db.do("INSERT INTO users SET login='#{username}', crypted_password='#{hashed_password}', created_at='#{time_now}'")
					user = $db.select_one("SELECT * FROM users WHERE login='#{username}'")
					ret['ok'] = true
					ret['user_id'] = user['id']
					return ret
				end
				ret['ok'] = false
				ret['error'] = "Username exists already"
				return ret
			end
		end
		ret['ok'] = false
		ret['error'] = "Not authenticated as admin"
		return ret
	end

	#function list_users: triggered when a "LIST USERS" message is received, returns a list of the users (only for administrators)
	def list_users(admin_username, admin_hashedpassword)
		#initializes the return variable
		ret = Hash.new
		admin = $db.select_one("SELECT * FROM users WHERE login='#{admin_username}'")
		if admin then
			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
				user_list = Array.new
				$db.select_all("SELECT * FROM users") do |ms|
					user=Hash.new
					user['id']=ms['id']
					user['username']=ms['login']
					user_list.push(user)
				end
				ret['ok'] = true
				ret['user_list'] = user_list
				return ret
			end
		end
		ret['ok'] = false
		ret['error'] = "Not authenticated as admin"
		return ret
	end

	#function change_passwd: triggered when a "CHANGE PASSWORD" message is received, modifies the password of a user
	def change_passwd(username, hashed_currentpassword, hashed_newpassword)
		#initializes the return variable
		ret = Hash.new
		user = $db.select_one "SELECT * FROM users WHERE login='#{username}'"
		if user then
			hashed_password_from_db = user['crypted_password']
			if (hashed_currentpassword == hashed_password_from_db) then
				$db.do("UPDATE users SET crypted_password='#{hashed_newpassword}' WHERE login='#{username}'")
				ret['ok'] = true
				return ret
			end
		end
		ret['ok'] = false
		ret['error'] = "Not authenticated"
		return ret
	end

	#function remove_user: triggered when a "REMOVE USER" message is received, deletes a user from the user table. Only
	#administrators can delete users
	def remove_user(username, admin_username, admin_hashedpassword)
		ret = Hash.new
		admin = $db.select_one("SELECT * FROM users WHERE login='#{admin_username}'")
		if admin then
			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
				user = $db.select_one("SELECT * FROM users WHERE login='#{username}'")
				if user then
					$db.do("DELETE FROM users WHERE login='#{username}'")
					ret['ok'] = true
					return ret
				end
				ret['ok'] = false
				ret['error'] = "User does not exist"
				return ret
			end
		end
		ret['ok'] = false
		ret['error'] = "Not authenticated as admin"
		return ret
	end

	private
	#function check_session_id: generic function that checks the validity of a session ID, and returns the corresponding
	#user ID if the session ID is valid
	def check_session_id(session_id)
		user = $db[:users].where('remember_token=?',session_id)
		if user then
			expires_at = user.get(:remember_token_expires_at)
			expires_at_time_format = Time.local(expires_at.year, expires_at.month, expires_at.day, expires_at.hour, expires_at.min, expires_at.sec)
			time_now = Time.new()
			if (time_now < expires_at_time_format) then
				ret = Hash.new
				ret['id'] = user.get(:id)
				ret['admin'] = user.get(:admin)
				return ret
			else
				user_id = user.get(:id)
        $db[:users].where('id=?',user_id).insert(:remember_token=>nil,:remember_token_expires_at=>nil)
				#$db.do("UPDATE users SET remember_token=NULL, remember_token_expires_at=NULL WHERE id=#{user_id}")
				return false
			end
		else
 			return false
		end
	end
end
