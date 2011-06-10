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


$dbt = DBUtils.get_new
# $new_dbt = DBUtils.get_new_mysql

class SplaydServer

	@@ssl = SplayControllerConfig::SSL
	@@splayd_threads = {}
	def self.threads() return @@splayd_threads end
	def self.threads=(threads) @@splayd_threads = threads end

	def initialize(port = nil)
		@port = port || SplayControllerConfig::SplaydPort
	end

	def run
		return Thread.new() do
			main
		end
	end

	def main
		begin
			server = TCPserver.new(@port)
			server.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)

			if @@ssl
				# SSL key and cert
				key = OpenSSL::PKey::RSA.new 512
				cert = OpenSSL::X509::Certificate.new
				cert.not_before = Time.now
				cert.not_after = Time.now + 3600
				cert.public_key = key.public_key
				cert.sign(key, OpenSSL::Digest::SHA1.new)

				# SSL context
				ctx = OpenSSL::SSL::SSLContext.new
				ctx.key = key
				ctx.cert = cert

				server = OpenSSL::SSL::SSLServer.new(server, ctx)

				$log.info("Waiting for splayds on port (SSL): " + @port.to_s)
			else
				$log.info("Waiting for splayds on port: " + @port.to_s)
			end
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			return
		end

		# Protect accept() For example, a bad SSL negociation makes accept()
		# to raise an exception. Can protect against that and a DOS.
		begin
			loop do
				so = server.accept
				SplaydProtocol.new(so).run
			end
		rescue => e
			$log.error(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			sleep 1
			retry
		end
	end
end

class SplaydProtocol
	
	class RegisterError < StandardError; end
	class ProtocolError < StandardError; end

	@@sleep_time = SplayControllerConfig::SPSleepTime
	@@ping_interval = SplayControllerConfig::SPPingInterval
	@@socket_timeout = SplayControllerConfig::SPSocketTimeout
	@@logd_ip = SplayControllerConfig::LogdIP
	@@logd_port = SplayControllerConfig::LogdPort
	@@log_max_size = SplayControllerConfig::LogMaxSize
	@@num_logd = SplayControllerConfig::NumLogd
	@@localize = SplayControllerConfig::Localize
	@@nat_gateway_ip = SplayControllerConfig::NATGatewayIP

	@splayd = nil
	@ip = nil
	@so_ori = nil
	@so = nil

	def initialize(so)
		@ip = so.peeraddr[3]
		@so_ori = so
		@so = LLenc.new(so)
		@so.set_timeout(@@socket_timeout)
	end

	def run
		return Thread.new do
			begin
				auth
				main
			rescue DBI::Error => e
				$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			rescue => e
				# "normal" situation
				$log.warn(e.class.to_s + ": " + e.to_s)
			ensure
				# When the thread is killed, this part is NOT threaded !
				if @splayd
					$log.info("Thread of splayd (#{@splayd}) will end now.")
				else
					$log.info("Thread of splayd (ip: #{@ip}) will end now.")
				end

				if @splayd
					SplaydServer.threads.delete(@splayd.id)
				end
				
				begin; @so_ori.close; rescue; end
			end
		end
	end

	def refused(msg)
		@so.write "REFUSED"
		@so.write msg
		raise RegisterError, msg
	end

	# Initialize splayd connection, authenticate, session, ...
	def auth
		$log.debug("A splayd (#{@ip}) try to connect.")

		if @so.read != "KEY" then raise ProtocolError, "KEY" end
		key = addslashes(@so.read)
		session = addslashes(@so.read)

		ok = true
		@splayd = Splayd.new(key)

		if not @splayd.id or @splayd.row['status'] == "DELETED"
			refused "That splayd doesn't exist: #{key}"
		end

		if @@nat_gateway_ip and @ip == @@nat_gateway_ip
			if key =~ /NAT_([^_]*)_.*/ or key =~ /NAT_(.*)/
				$log.info("#{@splayd}: IP change (NAT) from #{@ip} to #{$1}")
				@ip = $1
			else
				$log.info("#{@splayd}: IP of NAT gateway without replacement.")
			end
		end

    ## This restriction is way too restrictive, and it makes impossible
    ## to deploy several splayds on the same phisical machine, a typical
    ## scenario in cluster deployments.
		##if not @splayd.ip_check(@ip)
		##	refused "Your IP is already used by another splayd."
		##end

		if not @splayd.check_and_set_preavailable
			refused "Your splayd is already connected. " +
				 "Try to kill an existing process or wait " +
				 "2 minutes and retry."
		end

		# From here if there is not an external error (socket or db problem), the
		# splayd will be accepted.

		old_ip = @splayd.row['ip']
		begin
			SplaydServer.threads[@splayd.id] = Thread.current

			# update ip if needed
			if @ip != old_ip
				@splayd.update("ip", @ip)
			end

			# check if we can restore the session or not
			if session != @splayd.row['session'] or @ip != old_ip
				same = false
				@splayd.reset # (change session too)
			else
				same = true
			end

			@so.write "OK"
			@so.write @splayd.row['session']

			if same
				$log.info("#{@splayd}: Session OK")
			else
				@so.write "INFOS"
				@so.write @ip
				if @so.read != "OK" then raise ProtocolError, "INFOS not OK" end
				infos = @so.read # no addslashes (json)
				
				@splayd.insert_splayd_infos(infos)

				bl = Splayd.blacklist
				@so.write "BLACKLIST"
				@so.write bl.to_json
				if @so.read != "OK" then raise ProtocolError, "BLACKLIST not OK" end

				logv = {}
				logv['ip'] = @@logd_ip
				logv['port'] = @@logd_port + rand(@@num_logd)
				logv['max_size'] = @@log_max_size
				@so.write "LOG"
				@so.write logv.to_json
				if @so.read != "OK" then raise ProtocolError, "LOG not OK" end
				$log.info("#{@splayd}: Log port: #{logv['port']}")
			end
			$log.info("#{@splayd}: Auth OK")
			@splayd.available
		rescue => e
			# restore previous status (REGISTER, UNAVAILABLE or RESET)
			@splayd.update("status", @splayd.row['status'])
			raise e
		end

		if @ip != old_ip and @@localize
			$log.info("#{@splayd}: Localization")
			@splayd.localize
		end

		# TODO Invariant check @splayd.row must be == to a new fetch of infos
	end

	def main
		begin
			last_contact = @splayd.last_contact
			running = true
			while running
				action = @splayd.next_action

				if not action
					if Time.now.to_i - last_contact > @@ping_interval
						# "Inlining PING" Avoid 2 DB operations
						@so.write "PING"
						if @so.read != "OK" then raise ProtocolError, "PING not OK" end
						last_contact = @splayd.last_contact
					end
					sleep(rand(@@sleep_time * 2 * 100).to_f / 100)
				else

					$log.debug("#{@splayd}: Action #{action['command']}")

					start_time = Time.now.to_f
					@so.write action['command']
					if action['data']
						if action['command'] == 'LIST' and action['position']
							action['data'] = action['data'].sub(/_POSITION_/, action['position'].to_s)
						end
						@so.write action['data']
					end
					reply_code = @so.read
					if reply_code == "OK"
						if action['command'] == "REGISTER"
							port = addslashes(@so.read)
							reply_data = port
						end
						if action['command'] == "STATUS"
							reply_data = @so.read # no addslashes (json)
						end
						if action['command'] == "LOADAVG"
							reply_data = addslashes(@so.read)
						end
						if action['command'] == "HALT" or action['command'] == "KILL"
							running = false
						end
					end
					reply_time = Time.now.to_f - start_time



					# We tolerate some errors because one command
					# can be sent twice if there is a controller failure
					# juste after the send. But REGISTER can not have an
					# error because we don't re-send it, we send an
					# FREE then REGISTER again to avoid that.

					# All the @db.s_j_* functions are replayable.

					if action['command'] == "REGISTER"
						if reply_code == "OK"
							# Update the job slot from RESERVED to WAITING
							@splayd.s_j_register(action['job_id'])
							@splayd.s_sel_reply(action['job_id'], reply_data, reply_time)
						else
							raise ProtocolError, "REGISTER not OK: #{reply_code}"
						end
					end

					if action['command'] == "START"
						if reply_code == "OK" or reply_code == "RUNNING"
							@splayd.s_j_start(action['job_id'])
						else
							raise ProtocolError, "START not OK: #{reply_code}"
						end
					end

					if action['command'] == "STOP"
						if reply_code == "OK" or reply_code == "NOT_RUNNING"
							@splayd.s_j_stop(action['job_id'])
						else
							raise ProtocolError, "STOP not OK: #{reply_code}"
						end
					end

					if action['command'] == "FREE"
						@splayd.s_j_free(action['job_id'])
					end

					if action['command'] == "STATUS"
						@splayd.s_j_status(reply_data)
					end

					if action['command'] == "LOADAVG"
						@splayd.parse_loadavg(reply_data)
					end

					# We will remove the action here so, if the
					# controller crash between the reply and here, we
					# will do (or redo) the proper DB things.
					@splayd.remove_action(action)

					last_contact = @splayd.last_contact
				end
			end
		ensure
			@splayd.unavailable
			@splayd.action_failure
		end
	end
end

class Splayd

	attr_accessor :row
	attr_reader :id

	@@transaction_mutex = Mutex.new
	@@unseen_timeout = 3600
	@@auto_add = SplayControllerConfig::AutoAddSplayds

	def initialize(id)
		@row = $db.select_one "SELECT * FROM splayds WHERE id='#{id}'"
		if not @row
			@row = $db.select_one "SELECT * FROM splayds WHERE `key`='#{id}'"
		end
		if not @row and @@auto_add
			$log.info "Splayd #{id} Auto-added"
			$db.do "INSERT INTO splayds SET `key`='#{id}'"
			@row = $db.select_one "SELECT * FROM splayds WHERE `key`='#{id}'"
		end
		if @row then @id = @row['id'] end
	end

	def self.init
		$db.do "UPDATE splayds
				SET status='UNAVAILABLE'
				WHERE
				status='AVAILABLE' or status='PREAVAILABLE'"
		Splayd.reset_actions
		Splayd.reset_unseen
	end

	def self.reset_unseen
		$db.select_all "SELECT * FROM splayds WHERE
				last_contact_time<'#{Time.now.to_i - @@unseen_timeout}' AND
				(status='AVAILABLE' OR
				status='UNAVAILABLE' OR
				status='PREAVAILABLE')" do |splayd|
			$log.debug("Splayd #{splayd['id']} (#{splayd['ip']} - #{splayd['status']}) not seen " +
					"since #{@@unseen_timeout} seconds (#{splayd['last_contact_time']}) => RESET")
			# We kill the thread if there is one
			s = Splayd.new(splayd['id'])
			s.kill
			s.reset
		end
	end

	def self.reset_actions
		# When the controller start, if some actions where send but still not
		# replied, we will never receive the reply so we set the action to the
		# FAILURE status.
		$db.do "UPDATE actions SET status='FAILURE' WHERE status='SENDING'"

		# Uncomplete actions, jobd should put the again.
		$db.do "DELETE FROM actions WHERE status='TEMP'"
	end

	def self.gen_session
		return OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s + "session" + rand(1000000).to_s)
	end
	
	def self.has_job(splayd_id, job_id)
		sj = $db.select_one "SELECT * FROM splayd_jobs
				WHERE splayd_jobs.splayd_id='#{splayd_id}' AND
				splayd_jobs.job_id='#{job_id}'"
		if sj then return true else return false end
	end

	# Send an action to a splayd only if it is active.
	# For performance reasons, we will not check anymore the availability because
	# 99.9% of time, when an action is sent, the splayd is available. This should
	# have no consequences (other than a little DB space) because when the splayd
	# comes back from a reset state, it will be reset() and the commands deleted.
	def self.add_action(splayd_id, job_id, command, data = '')
		$db.do "INSERT INTO actions SET
				splayd_id='#{splayd_id}',
				job_id='#{job_id}',
				command='#{command}',
				data='#{addslashes data}'"
		return true

		# full version follow (when not running in controller :-)
		#splayd = $db.select_one "SELECT status FROM splayds WHERE id='#{splayd_id}'"
		# Even UNAVAILABLE, the splayd IS active !
		#if splayd['status'] == 'AVAILABLE' or splayd['status'] == 'UNAVAILABLE'
			#$db.do "INSERT INTO actions SET
					#splayd_id='#{splayd_id}',
					#job_id='#{job_id}',
					#command='#{command}',
					#data='#{addslashes data}'"
			#true
		#else
			#false
		#end
	end

	def self.blacklist
		hosts = []
		$db.select_all "SELECT host FROM blacklist_hosts" do |row|
			hosts << row[0]
		end
		return hosts
	end

	def self.localize_all
		return Thread.new do
			$db.select_all "SELECT id FROM splayds" do |s|
				splayd = Splayd.new(s['id'])
				splayd.localize
			end
		end
	end

	def to_s
		if @row['name'] and @row['ip']
			return "#{@id} (#{@row['name']}, #{@row['ip']})"
		elsif @row['ip']
			return "#{@id} (#{@row['ip']})"
		else
			return "#{@id}"
		end
	end

	def check_and_set_preavailable
		r = false
		# to protect the $dbt object while in use.
		@@transaction_mutex.synchronize do
			#$dbt.transaction do |dbt|
			$dbt.do "BEGIN"
				status = ($dbt.select_one "SELECT status FROM splayds
						  WHERE id='#{@id}' FOR UPDATE")['status']
				if status == 'REGISTERED' or status == 'UNAVAILABLE' or status == 'RESET' then
					$dbt.do "UPDATE splayds SET
							status='PREAVAILABLE'
							WHERE id ='#{@id}'"
					r = true
				end
			$dbt.do "COMMIT"
			#end
		end
		return r
	end

	# Check that this IP is not used by another splayd.
	def ip_check ip
		if ip == "127.0.0.1" or ip=="::ffff:127.0.0.1" or not $db.select_one "SELECT * FROM splayds WHERE
				ip='#{ip}' AND
				`key`!='#{@row['key']}' AND
				(status='AVAILABLE' OR status='UNAVAILABLE' OR status='PREAVAILABLE')"
			true
		else
			false
		end
	end

	def insert_splayd_infos infos
		infos = JSON.parse infos

		if infos['status']['endianness'] == 0
			infos['status']['endianness'] = "little"
		else
			infos['status']['endianness'] = "big"
		end

		# We don't update ip, key, session and localization infomrations here
		$db.do "UPDATE splayds SET
				name='#{addslashes(infos['settings']['name'])}',
				version='#{addslashes(infos['status']['version'])}',
				lua_version='#{addslashes(infos['status']['lua_version'])}',
				bits='#{addslashes(infos['status']['bits'])}',
				endianness='#{addslashes(infos['status']['endianness'])}',
				os='#{addslashes(infos['status']['os'])}',
				full_os='#{addslashes(infos['status']['full_os'])}',
				start_time='#{addslashes((Time.now.to_f - infos['status']['uptime'].to_f).to_i)}',
				max_number='#{addslashes(infos['settings']['job']['max_number'])}',
				max_mem='#{addslashes(infos['settings']['job']['max_mem'])}',
				disk_max_size='#{addslashes(infos['settings']['job']['disk']['max_size'])}',
				disk_max_files='#{addslashes(infos['settings']['job']['disk']['max_files'])}',
				disk_max_file_descriptors='#{addslashes(infos['settings']['job']['disk']['max_file_descriptors'])}',
				network_max_send='#{addslashes(infos['settings']['job']['network']['max_send'])}',
				network_max_receive='#{addslashes(infos['settings']['job']['network']['max_receive'])}',
				network_max_sockets='#{addslashes(infos['settings']['job']['network']['max_sockets'])}',
				network_max_ports='#{addslashes(infos['settings']['job']['network']['max_ports'])}',
				network_send_speed='#{addslashes(infos['settings']['network']['send_speed'])}',
				network_receive_speed='#{addslashes(infos['settings']['network']['receive_speed'])}'
				WHERE id='#{@id}'"

		parse_loadavg(infos['status']['loadavg'])
	end

	def localize
		if @row['ip'] and
				not @row['ip'] == "127.0.0.1" and
				not @row['ip'] =~ /192\.168\..*/ and
				not @row['ip'] =~ /10\.0\..*/

			$log.debug("Trying to localize: #{@row['ip']}")
			begin
				hostname = ""
				begin
					Timeout::timeout(10, StandardError) do
						hostname = Resolv::getname(@row['ip'])
					end
				rescue
					$log.warn("Timeout resolving hostname of IP: #{@row['ip']}")
				end
				loc = Localization.get(@row['ip'])
				$log.info("#{@id} #{@row['ip']} #{hostname} " +
						"#{loc.country_code.downcase} #{loc.city}")
				$db.do "UPDATE splayds SET
						hostname='#{hostname}',
						country='#{loc.country_code.downcase}',
						city='#{loc.city}',
						latitude='#{loc.latitude}',
						longitude='#{loc.longitude}'
						WHERE id='#{@id}'"
			rescue => e
				puts e
				$log.error("Impossible localization of #{@row['ip']}")
			end
		end
	end

	def remove_action action
		$db.do "DELETE FROM actions WHERE id='#{action['id']}'"
	end

	def update(field, value)
		$db.do "UPDATE splayds SET #{field}='#{value}' WHERE id='#{@id}'"
		@row[field] = value
	end

	def kill
		if SplaydServer.threads[@id]
			SplaydServer.threads.delete(@id).kill
		end
	end

	# DB cleaning when a splayd is reset.
	def reset
		@row['session'] = Splayd.gen_session
		$db.do "UPDATE splayds SET
				status='RESET', session='#{@row['session']}' WHERE id='#{@id}'"
		$db.do "DELETE FROM actions WHERE splayd_id='#{@id}'"
		$db.do "DELETE FROM splayd_jobs WHERE splayd_id='#{@id}'"
		$db.do "INSERT INTO splayd_availabilities SET
			  splayd_id='#{@id}', status='RESET', time='#{Time.now.to_i}'"
		# for trace job
		$db.do "UPDATE splayd_selections SET reset='TRUE' WHERE splayd_id='#{@id}'"
	end

	def unavailable
		$db.do "UPDATE splayds SET status='UNAVAILABLE' WHERE id='#{@id}'"
		$db.do "INSERT INTO splayd_availabilities SET
			   splayd_id='#{@id}',
			   status='UNAVAILABLE',
			   time='#{Time.now.to_i}'"
	end

	def action_failure
		$db.do "UPDATE actions SET status='FAILURE'
				WHERE status='SENDING' AND splayd_id='#{@id}'"
	end

	def available
		$db.do "UPDATE splayds SET status='AVAILABLE' WHERE id='#{@id}'"
		$db.do "INSERT INTO splayd_availabilities SET
			   splayd_id='#{@id}',
			   ip='#{@row['ip']}',
			   status='AVAILABLE',
			   time='#{Time.now.to_i}'"
		last_contact
		restore_actions
	end

	def last_contact
		$db.do "UPDATE splayds SET
			   last_contact_time='#{Time.now.to_i}' WHERE id='#{@id}'"
		return Time.now.to_i
	end

	# Restore actions in failure state.
	def restore_actions
		$db.select_all "SELECT * FROM actions WHERE
				status='FAILURE' AND
				splayd_id='#{@id}'" do |action|

			if action['command'] == 'REGISTER'
				# We should put the FREE-REGISTER at the same place
				# where REGISTER was. But, no other register action concerning
				# this splayd and this job can exists (because registering is
				# split into states), so, if we remove the REGISTER, we can safely
				# add the FREE-REGISTER commands at the top of the
				# actions.
				job = $db.select_one "SELECT ref FROM jobs WHERE id='#{action['job_id']}'"
				$db.do "DELETE FROM actions WHERE id='#{action['id']}'"
				Splayd.add_action(action['splayd_id'], action['job_id'], 'FREE', job['ref'])
				Splayd.add_action(action['splayd_id'], action['job_id'], 'REGISTER', addslashes(job['code']))
			else
				$db.do "UPDATE actions SET status='WAITING' WHERE id='#{action['id']}'"
			end
		end
	end

	# Return the next WAITING action and set status to SENDING.
	def next_action
		action = $db.select_one "SELECT * FROM actions WHERE
				splayd_id='#{@id}' ORDER BY id LIMIT 1"
		if action 
			if action['status'] == 'TEMP'
				$log.info("INCOMPLETE ACTION: #{action['command']} " +
							"(splayd: #{@id}, job: #{action['job_id']})")
			end
			if action['status'] == 'WAITING'
				$db.do "UPDATE actions SET
						status='SENDING'
						WHERE id='#{action['id']}'"
				return action
			end
		end
		nil
	end

	def s_j_register job_id
		$db.do "UPDATE splayd_jobs SET
				status='WAITING'
				WHERE
				splayd_id='#{@id}' AND
				job_id='#{job_id}' AND
				status='RESERVED'"
	end

	def s_j_free job_id
		$db.do "DELETE FROM splayd_jobs WHERE
				splayd_id='#{@id}' AND
				job_id='#{job_id}'"
	end

	def s_j_start job_id
		$db.do "UPDATE splayd_jobs SET
			  status='RUNNING'
			  WHERE
			  splayd_id='#{@id}' AND
			  job_id='#{job_id}'"
	end

	def s_j_stop job_id
		$db.do "UPDATE splayd_jobs SET
			  status='WAITING'
			  WHERE
			  splayd_id='#{@id}' AND
			  job_id='#{job_id}'"
	end

	def s_j_status data
		data = JSON.parse data
		$db.select_all "SELECT * FROM splayd_jobs WHERE
				splayd_id='#{@id}' AND
				status!='RESERVED'" do |sj|
			job = $db.select_one "SELECT ref FROM jobs WHERE id='#{sj['job_id']}'"
			# There is no difference in Lua between Hash and Array, so when it's
			# empty (an Hash), we encoded it like an empy Array.
			if data['jobs'].class == Hash and data['jobs'][job['ref']]
				if data['jobs'][job['ref']]['status'] == "waiting"
					$db.do "UPDATE splayd_jobs SET status='WAITING'
							WHERE id='#{sj['id']}'"
				end
				# NOTE normally no needed because already set to RUNNING when
				# we send the START command.
				if data['jobs'][job['ref']]['status'] == "running"
					$db.do "UPDATE splayd_jobs SET status='RUNNING'
							WHERE id='#{sj['id']}'"
				end

			else
				$db.do "DELETE FROM splayd_jobs WHERE id='#{sj['id']}'"
			end
			# it can't be new jobs in data['jobs'] that don't have already an
			# entry in splayd_jobs
		end
	end

	def parse_loadavg s
		if s.strip != ""
			l = s.split(" ")
			$db.do "UPDATE splayds SET
					load_1='#{l[0]}',
					load_5='#{l[1]}',
					load_15='#{l[2]}'
					WHERE id='#{@id}'"
		else
			# NOTE should too be fixed in splayd
			$log.warn("Splayd #{@id} report an empty loadavg. ")
			$db.do "UPDATE splayds SET
					load_1='10',
					load_5='10',
					load_15='10'
					WHERE id='#{@id}'"
		end
	end
	
	# NOTE then corresponding entry may already have been deleted if the reply
	# comes after the job has finished his registration, but no problem.
	def s_sel_reply(job_id, port, reply_time)
		$db.do "UPDATE splayd_selections SET
				replied='TRUE',
				reply_time='#{reply_time}',
				port='#{port}'
				WHERE splayd_id='#{@id}' AND job_id='#{job_id}'"
	end
end
