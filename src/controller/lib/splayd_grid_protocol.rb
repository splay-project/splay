require File.expand_path(File.join(File.dirname(__FILE__), 'splayd_protocol'))

class SplaydGridProtocol < SplaydProtocol
  
  def auth_update_lib
    #$log.info( "auth_update_lib")
    in_table = @so.read # sent through json
    $log.debug(in_table)
    in_table = JSON.parse(in_table)
    #$log.info("receive library list:")
    
    out_table = []
    #UPDATE  libs that exist on the splayds
    # LIST ALL SHA1
    old_libs = []
    # DELETE ALL AND ADD OLD BUT VALID AND  THE NEW LIBS INTO THE TABLE splayd_libs
    $db.do("DELETE FROM splayd_libs WHERE splayd_id='#{@splayd.row['id']}'")
    
    in_table.each do |lib_pair|
      tmp_lib = $db[:libs].where(lib_sha1=>"#{lib_pair['sha1']}") #.fetch("SELECT * FROM libs WHERE lib_sha1='#{lib_pair['sha1']}'")
      if tmp_lib then
        $db.do("INSERT INTO splayd_libs SET splayd_id='#{@splayd.row['id']}', lib_id='#{tmp_lib['id']}' ")
      else
        old_libs.push(lib_pair)
      end
    end
    
    old_libs_json = JSON.unparse(old_libs)
    @so.write old_libs_json
    if @so.read != "OK" then raise ProtocolError, "UPDATE LIB NOT OK" end
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
					lib_id = nil
					start_time = Time.now.to_f
					@so.write action['command']
					if action['data']
						if action['command'] == 'LIST' and action['position']
							action['data'] = action['data'].sub(/_POSITION_/, action['position'].to_s)
						elsif action['command'] == "REGISTER"
							job = action['data']
							job = JSON.parse(job)
							if job['lib_name' ] && job['lib_name'] != ""
								lib = $db.fetch("SELECT * FROM splayd_libs, libs WHERE splayd_libs.lib_id=libs.id AND splayd_libs.splayd_id=#{@splayd.row['id']} 
	                                      AND libs.lib_name='#{job['lib_name']}' AND libs.lib_version='#{job['lib_version']}'")
	                			if not lib #$log.debug("Send the lib to the splayd and add it in splayd_libs #{@splayd.row['architecture']} AND lib_os=#{@splayd['os']}")
	                  				lib = $db.fetch("SELECT * FROM libs WHERE lib_name='#{job['lib_name']}' AND lib_version='#{job['lib_version']}' 
	                                        AND lib_arch='#{@splayd.row['architecture']}' AND lib_os='#{@splayd.row['os']}'")
	                  				job['lib_code'] = lib['lib_blob']
	                				job['lib_sha1'] = lib['lib_sha1']
	                				lib_id = lib['id']
	                			end
	                			job['lib_sha1'] = lib['lib_sha1']
	                			job = job.to_json
	                			action['data'] = job
	              			end
						end
						@so.write action['data']
					end
					reply_code = @so.read
					if reply_code == "OK"
						if action['command'] == "REGISTER"
						  if lib_id != nil then $db.do("INSERT INTO splayd_libs SET splayd_id='#{@splayd.row['id']}', lib_id='#{lib_id}'") end
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