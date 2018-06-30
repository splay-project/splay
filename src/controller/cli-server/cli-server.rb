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

require 'webrick'
require 'rubygems'
require 'orbjson'
require '../lib/common.rb'
#library required for hashing
require 'digest/sha1'

$logger = Logger.new( "orbjson.log" )
$logger.level = Logger::DEBUG

class ChangePasswd < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = change_passwd(
      req['params'][0],
      req['params'][1],
      req['params'][2]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  #function change_passwd: triggered when a "CHANGE PASSWORD" message is received, modifies the password of a user
	def change_passwd(username, hashed_currentpassword, hashed_newpassword)
		#initializes the return variable
		# ret = Hash.new
		user = $db.select_all "SELECT * FROM users WHERE login='#{username}'"
		if user then
      user = user.first
			hashed_password_from_db = user['crypted_password']
			if (hashed_currentpassword == hashed_password_from_db) then
				$db.do("UPDATE users SET crypted_password='#{hashed_newpassword}' WHERE login='#{username}'")
				return 200, 'text/plain', '{"result": {"ok": true}}'
			end
		end
		return 400, 'text/plain', '{"result": {"ok": false, "error": ""}}'
	end

end

class GetLog < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = get_log(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  #function get_log: triggered when a "GET LOG" message is received, returns the corresponding log file as a string
	def get_log(job_id, session_id)
		#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID
		# is valid)
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
				return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "log": ' + ret['log'].to_s + '}}'
			end
			#if the 'if (user)' statement was true, the function would have ended with the return on the line above,
			# if not, the following lines are processed
			#ok is false
			ret['ok'] = false
			if user['admin'] == 1 then
				ret['error'] = "Job does not exist"
			else
				#error says that the job doesn't exist
				ret['error'] = "Job does not exist for this user"
			end
			#returns ret
			return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
		end
		#if session ID wa+ ', "log": ' + ret['log']s not valid, ok is false
		ret['ok'] = false
		#error says that the session ID was invalid
		ret['error'] = "Invalid or expired Session ID"
		#returns ret
		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
	end
end

class GetJobCode < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = get_job_code(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  #function get_job_code: triggered when a "GET JOB CODE" message is received, returns the corresponding
  # source code as a string
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
  			job = $db.select_all("SELECT * FROM jobs WHERE id=#{job_id}")
  			#if job exists
  			if job then
          job = job.first
  				#if the user is admin (can see all the jobs) or the job belongs to her
  				if ((user['admin'] == 1) or (job['user_id'] == user_id)) then
  					#ok is true
  					ret['ok'] = true
  					#code is a string containing the code
  					ret['code'] = job['code']
  					#returns ret
  					return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "code": ' + ret['code'] + '}}'
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
  			return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  		end
  		#if session ID was not valid, ok is false
  		ret['ok'] = false
  		#error says that the session ID was invalid
  		ret['error'] = "Invalid or expired Session ID"
  		#returns ret
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class KillJob < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = kill_job(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
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
  				# to kill the job
  				$db.do("UPDATE jobs SET command='KILL' WHERE id='#{job_id}'")
  				#ok is true
  				ret['ok'] = true
  				#returns ret
  				return 200, 'text/plain', '{"result": {"ok": ' + ret['ok'].to_s + '}}'
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
  		return 500, 'text/plain', '{"result": {"ok": ' + ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class SubmitJob < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    p req
    status, content_type, body = submit_job(
      req['params'][0],
      req['params'][1],
      req['params'][2],
      req['params'][3],
      req['params'][4],
      req['params'][5],
      req['params'][6]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

	#function submit_job: triggered when a "SUBMIT JOB" message is received, submits a job to the controller
	def submit_job(name, description, code, nb_splayds, churn_trace, options, session_id)
	 	#initializes the return variable
		ret = Hash.new
		#checks the validity of the session ID and stores the returning value in the variable user
		user = check_session_id(session_id)
		#check_session_id returns false if the session ID is not valid; if user is not false (the session ID is valid)
		if (user) then
			ref = OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s)
			#user_id is taken from the field 'id' from variable user
			user_id = user['id']

			time_now = Time.new().strftime("%Y-%m-%d %T")

			if options.class == Array then
				options = Hash.new
			end
			if nb_splayds then
				if (nb_splayds>0) then
					options['nb_splayds'] = nb_splayds
				end
			end

			if description == "" then
				description_field = ""
			else
				description_field = "description='#{description}',"
			end

			if name == "" then
				name_field = ""
			else
				name_field = "name='#{name}',"
			end

			if churn_trace == "" then
				churn_field = ""
			else
				options['nb_splayds'] = 0
				churn_trace.lines do |line|
					options['nb_splayds'] = options['nb_splayds'] + 1
				end
				options['scheduler'] = 'trace'
				churn_field = "die_free='FALSE', scheduler_description='#{addslashes(churn_trace)}',"
			end

			$db.do("INSERT INTO jobs SET ref='#{ref}' #{to_sql(options)}, #{description_field} #{name_field} #{churn_field} code='#{addslashes(code)}', user_id=#{user_id}, created_at='#{time_now}'")

			timeout = 30
			while timeout > 0
				sleep(1)
				timeout = timeout - 1
				job = $db.select_all("SELECT * FROM jobs WHERE ref='#{ref}'")
        if job then
          job = job.first
          if job['status'] == "RUNNING" then
            ret['ok'] = true
            ret['job_id'] = job['id']
            ret['ref'] = ref
            return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "job_id": ' + ret['job_id'].to_s + ', "ref": ' + ret['ref'].to_s + '}}'
          end
          if job['status'] == "NO_RESSOURCES" then
            ret['ok'] = false
            ret['error'] = "JOB " + job['id'].to_s + ": " + job['status_msg']
            return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": "' + ret['error'] + '"}}'
          end
        end
			end
			#if timeout reached 0, ok is false
			ret['ok'] = false
			#error says that a timeout occured and suggests to check if the controller is running
			ret['error'] = "JOB " + job['id'].to_s + ": timeout; please check if controller is running"
			#returns ret
			return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": "' + ret['error'] + '"}}'
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": "' + ret['error'] + '"}}'
	end

end

class GetJobDetails < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = get_job_details(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
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
  					m = $db.select_all("SELECT * FROM splayds WHERE id='#{ms['splayd_id']}'")
            if m then
              m = m.first
              host = Hash.new
              host['splayd_id'] = ms['splayd_id']
              host['ip'] = m['ip']
              host['port'] = ms['port']
              host_list.push(host)
            end
  				end
  				job = $db.select_all("SELECT * FROM jobs WHERE id=#{job_id}")
          if job then
            job = job.first
            ret['ok'] = true
            str = ''
            host_list.each do |h|
              str += h.to_json + ','
            end
            ret['host_list'] = '[' + str + ']'
            ret['status'] = job['status']
            ret['ref'] = job['ref']
            ret['name'] = job['name']
            ret['description'] = job['description']
            ret['user_id'] = "NO_ADMIN"
            if (user['admin'] == 1) then
              ret['user_id'] = job['user_id']
            end
            return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "host_list": ' + ret['host_list'] + ', "status": ' + ret['status'].to_s + ', "ref": ' + ret['ref'].to_s + ', "name": ' + ret['name'].to_s + ', "description": ' + ret['description'].to_s + ', "user_id": ' + ret['user_id'].to_s + '}}'
          else
            ret['ok'] = false
            ret['error'] = "Job does not exist for this user"
            return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
          end
  			end
  			ret['ok'] = false
  			if user['admin'] == 1 then
  				ret['error'] = "Job does not exist"
  			else
  				#error says that the job doesn't exist
  				ret['error'] = "Job does not exist for this user"
  			end
  			return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  		end
  		ret['ok'] = false
  		ret['error'] = "Invalid or expired Session ID"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class ListJobs < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = list_jobs(
      req['params'][0]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
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
				$db.select_all("SELECT * FROM jobs") do |ms|
					job = Hash.new
					job['id'] = ms['id']
					job['status'] = ms['status']
					job['user_id'] = ms['user_id']
					job_list.push(job)
				end
			else
				$db.select_all("SELECT * FROM jobs WHERE user_id=#{user_id}") do |ms|
					job = Hash.new
					job['id'] = ms['id']
					job['status'] = ms['status']
					job_list.push(job)
				end
			end
			ret['ok'] = true
      str = ''
      job_list.each do |j|
        str += j.to_json + ','
      end
			ret['job_list'] = '[' + str + ']'
			return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "job_list": ' + ret['job_list'] + '}}'
		end
		ret['ok'] = false
		ret['error'] = "Invalid or expired Session ID"
		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
	end

end

class ListSplayds < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = list_splayds(
      req['params'][0]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
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
        str = ''
        splayd_list.each do |spl|
          str += spl.to_json + ','
        end
  			ret['splayd_list'] = '[' + str + ']'
  			return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "splayd_list": ' + ret['splayd_list'] + '}}'
  		end
  		ret['ok'] = false
  		ret['error'] = "Invalid or expired Session ID"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class StartSession < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = start_session(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  	#function start_session: triggered when a "START SESSION" message is received, triggers the granting of a token or session
  	#ID valid for 24h, and returns this token along with the expiry date
  	def start_session(username, hashed_password)
  		#initializes the return variable
  		ret = Hash.new
  		user = $db.select_all "SELECT * FROM users WHERE login='#{username}'"
  		if user then
        user = user.first
  			hashed_password_from_db = user['crypted_password']
  			if (hashed_password == hashed_password_from_db) then
  				time_tomorrow = Time.new + 3600*24
  				remember_token_expires_at = time_tomorrow.strftime("%Y-%m-%d %T")
  				remember_token = Digest::SHA1.hexdigest("#{username}--#{remember_token_expires_at}")
  				$db.do("UPDATE users SET remember_token='#{remember_token}', remember_token_expires_at='#{remember_token_expires_at}' WHERE login='#{username}'")
  				ret['ok'] = true
  				ret['session_id'] = '"' + remember_token + '"'
  				ret['expires_at'] = '"' + remember_token_expires_at + '"'
  				return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "session_id": ' + ret['session_id'] + ', "expires_at": ' + ret['expires_at'] + '}}'
  			end
  		end
  		ret['ok'] = false
  		ret['error'] = "Not authenticated"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class NewUser < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = new_user(
      req['params'][0],
      req['params'][1],
      req['params'][2],
      req['params'][3]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  	#function new_user: triggered when a "NEW USER" message is received, creates a new regular user
  	def new_user(username, hashed_password, admin_username, admin_hashedpassword)
  		#initializes the return variable
  		ret = Hash.new
  		admin = $db.select_all("SELECT * FROM users WHERE login='#{admin_username}'")
  		if admin then
        admin = admin.first
  			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
  				if not ($db.select_one("SELECT * FROM users WHERE login='#{username}'")) then
  					time_now = Time.new().strftime("%Y-%m-%d %T")
  					$db.do("INSERT INTO users SET login='#{username}', crypted_password='#{hashed_password}', created_at='#{time_now}'")
  					user = $db.select_one("SELECT * FROM users WHERE login='#{username}'")
  					ret['ok'] = true
  					ret['user_id'] = user['id']
  					return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "user_id": ' + ret['user_id'].to_s + '}}'
  				end
  				ret['ok'] = false
  				ret['error'] = "Username exists already"
  				return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  			end
  		end
  		ret['ok'] = false
  		ret['error'] = "Not authenticated as admin"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

class ListUsers < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = list_users(
      req['params'][0],
      req['params'][1]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  	#function list_users: triggered when a "LIST USERS" message is received, returns a list of the users (only for administrators)
  	def list_users(admin_username, admin_hashedpassword)
  		#initializes the return variable
  		ret = Hash.new
  		admin = $db.select_all("SELECT * FROM users WHERE login='#{admin_username}'")
  		if admin then
        admin = admin.first
  			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
  				user_list = Array.new
  				$db.select_all("SELECT * FROM users") do |ms|
  					user=Hash.new
  					user['id']=ms['id']
  					user['username']=ms['login']
  					user_list.push(user)
  				end
  				ret['ok'] = true
          r = ''
          user_list.each do |u|
            r += u.to_json + ','
          end
  				ret['user_list'] = '[' + r + ']'
  				return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "user_list": ' + ret['user_list'] + '}}'
  			end
  		end
  		ret['ok'] = false
  		ret['error'] = "Not authenticated as admin"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end

end

class RemoveUser < WEBrick::HTTPServlet::AbstractServlet

  def do_POST(request, response)
    req = JSON.parse(request.body)
    status, content_type, body = remove_user(
      req['params'][0],
      req['params'][1],
      req['params'][2]
    )
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end

  	#function remove_user: triggered when a "REMOVE USER" message is received, deletes a user from the user table. Only
  	#administrators can delete users
  	def remove_user(username, admin_username, admin_hashedpassword)
  		ret = Hash.new
  		admin = $db.select_all("SELECT * FROM users WHERE login='#{admin_username}'")
  		if admin then
        admin = admin.first
  			if ((admin['crypted_password'] == admin_hashedpassword) and (admin['admin'] == 1)) then
  				user = $db.select_one("SELECT * FROM users WHERE login='#{username}'")
  				if user then
  					$db.do("DELETE FROM users WHERE login='#{username}'")
  					ret['ok'] = true
  					return 200, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + '}}'
  				end
  				ret['ok'] = false
  				ret['error'] = "User does not exist"
  				return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  			end
  		end
  		ret['ok'] = false
  		ret['error'] = "Not authenticated as admin"
  		return 500, 'text/plain', '{"result": {"ok": ' +ret['ok'].to_s + ', "error": ' + ret['error'] + '}}'
  	end
end

# 	private
#function check_session_id: generic function that checks the validity of a session ID, and returns the corresponding
#user ID if the session ID is valid
def check_session_id(session_id)
	user = $db.select_all("SELECT * FROM users WHERE remember_token='#{session_id}'")
	if user then
    p user
    user = user.first
		expires_at = user['remember_token_expires_at']
		expires_at_time_format = Time.local(expires_at.year, expires_at.month, expires_at.day, expires_at.hour, expires_at.min, expires_at.sec)
		time_now = Time.new()
		if (time_now < expires_at_time_format) then
			ret = Hash.new
			ret['id'] = user['id']
			ret['admin'] = user['admin']
			return ret
		else
			user_id = user['id']
			$db.do("UPDATE users SET remember_token=NULL, remember_token_expires_at=NULL WHERE id=#{user_id}")
			return false
		end
	else
			return false
	end
end

if $0 == __FILE__ then
  server = WEBrick::HTTPServer.new(:Port => 8080)
  server.mount "/change_passwd", ChangePasswd
  server.mount "/get_log", GetLog
  server.mount "/get_job_code", GetJobCode
  server.mount "/get_job_details", GetJobDetails
  server.mount "/kill_job", KillJob
  server.mount "/list_jobs", ListJobs
  server.mount "/list_splayds", ListSplayds
  server.mount "/list_users", ListUsers
  server.mount "/submit_job", SubmitJob
  server.mount "/start_session", StartSession
  server.mount "/new_user", NewUser
  server.mount "/remove_user", RemoveUser
  trap "INT" do server.shutdown end
  server.start
end
