require File.expand_path(File.join(File.dirname(__FILE__), 'splayd'))

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
  @id = nil

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
					$log.info("Thread of splayd (#{@row[:key]}) will end now.")
				else
					$log.info("Thread of splayd (ip: #{@ip}) will end now.")
				end

				if @splayd
					SplaydServer.threads.delete(@id)
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
  
  # 
  def pre_auth
  end
  #
 	def auth_update_lib
  end
	# Initialize splayd connection, authenticate, session, ...
	def auth
   	if @so.read != "KEY" then raise ProtocolError, "KEY" end
		key = addslashes(@so.read)
		session = addslashes(@so.read)
    p "#{key} #{session}"
		ok = true
		@splayd = Splayd.new(key)
    p "New splayd created: #{@splayd}"
		if not @row[:id] or @row[:status] == "DELETED"
			refused "That splayd doesn't exist or was deleted: #{key}"
		end

		if @@nat_gateway_ip and @ip == @@nat_gateway_ip
			if key =~ /NAT_([^_]*)_.*/ or key =~ /NAT_(.*)/
				$log.info("#{@splayd}: IP change (NAT) from #{@ip} to #{$1}")
				@ip = $1
			else
				$log.info("#{@splayd[:id]}: IP of NAT gateway without replacement.")
			end
		end
    
		if not @splayd.check_and_set_preavailable
			refused "Your splayd is already connected. " +
				 "Try to kill an existing process or wait " +
				 "2 minutes and retry."
		end
    
		# From here if there is not an external error (socket or db problem), the
		# splayd will be accepted.

		old_ip = @row[:ip]
		begin
			SplaydServer.threads[@id] = Thread.current

			# update ip if needed
			if @ip != old_ip
				@splayd.update(:ip=>@ip)
			end

			# check if we can restore the session or not
			if session != @splayd[:session] or @ip != old_ip
				same = false
				@splayd.reset # (change session too)
			else
				same = true
			end

      # Implemented only in JobdGrid as of now
      auth_update_lib()

			@so.write "OK"
			@so.write @splayd[:session]

			if same
				$log.info("#{@splayd}: Session OK")
			else
				@so.write "INFOS"
				@so.write @ip
				if @so.read != "OK" then raise ProtocolError, "INFOS not OK" end
				infos = @so.read # no addslashes (json)
			  
				@splayd.insert_splayd_infos(infos)
				@splayd.update_splayd_infos()

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
