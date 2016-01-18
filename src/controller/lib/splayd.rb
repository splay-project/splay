$dbt = DBUtils.get_new_mysql_sequel
# $new_dbt = DBUtils.get_new_mysql

class Splayd

	attr_accessor :row
	attr_reader :id

	@@transaction_mutex = Mutex.new
	@@unseen_timeout = 3600
	@@auto_add = SplayControllerConfig::AutoAddSplayds
  
  @row = nil #a pointer to the row in the database for this splayd
  
	def initialize(id)
    @row = $db[:splayds].first(:id=>id)
	  if not @row
			@row = $db[:splayds].first(:key=>id)
		end
    if not @row and @@auto_add
			$db[:splayds].insert(:key=>id)
			@row = $db[:splayds].where(:key=>id)
		end
		if @row then
       @id = @row.get(:id)
     end
    $log.debug("Splayd #{id} initialized")
 	end

	def self.init
    $db[:splayds].where{status=='AVAILABLE' || status=='PREAVAILABLE'}.update(:status=>'UNAVAILABLE')
	  #$db.do "UPDATE splayds
		#		SET status='UNAVAILABLE'
		#		WHERE
		#		status='AVAILABLE' or status='PREAVAILABLE'"
		Splayd.reset_actions
		Splayd.reset_unseen
	end

	def self.reset_unseen
		$db.fetch "SELECT * FROM splayds WHERE
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
		#$db.do "UPDATE actions SET status='FAILURE' WHERE status='SENDING'"
    $db[:actions].where(:status=>'SENDING').update(:status=>'FAILURE')
		# Uncomplete actions, jobd should put the again.
		$db[:actions].where(:status=>'TEMP').delete #$db.do "DELETE FROM actions WHERE status='TEMP'"
	end

	def self.gen_session
		return OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s + "session" + rand(1000000).to_s)
	end
	
	def self.has_job(splayd_id, job_id)
		sj = $db.fetch "SELECT * FROM splayd_jobs
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
		$db[:blacklist_hosts].select(:host) do |row| #.select_all "SELECT host FROM blacklist_hosts"
			hosts << row[0]
		end
		return hosts
	end

	def self.localize_all
		return Thread.new do
			$db[:splayds].select(:id) do |s| #.select_all "SELECT id FROM splayds"
				splayd = Splayd.new(s['id'])
				splayd.localize
			end
		end
	end

	def to_s
		if @row['name'] and @row['ip']
			return "#{@id} (#{@row.get(:name)}, #{@row.get(:ip)})"
		elsif @row['ip']
			return "#{@id} (#{@row.get(:ip)})"
		else
			return "#{@id}"
		end
	end

	def check_and_set_preavailable
  	r = false
		# to protect the $dbt object while in use.
		@@transaction_mutex.synchronize do
			$dbt.transaction do
        status= $dbt[:splayds].where(:id=>@id).get(:status)
       	if status == 'REGISTERED' or status == 'UNAVAILABLE' or status == 'RESET' then
					$dbt.do "UPDATE splayds SET
							status='PREAVAILABLE'
							WHERE id ='#{@id}'"
					r = true
				end
			end # COMMIT issued only here
		end
		return r
	end

	# Check that this IP is not used by another splayd.
	def ip_check ip
		if ip == "127.0.0.1" or ip=="::ffff:127.0.0.1" or not $db.fetch "SELECT * FROM splayds WHERE
				ip='#{ip}' AND
				`key`!='#{@row.get(:key)}' AND
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
				protocol='#{addslashes(infos['settings']['protocol'])}',
				lua_version='#{addslashes(infos['status']['lua_version'])}',
				bits='#{addslashes(infos['status']['bits'])}',
				endianness='#{addslashes(infos['status']['endianness'])}',
				os='#{addslashes(infos['status']['os'])}',
				full_os='#{addslashes(infos['status']['full_os'])}',
				architecture='#{addslashes(infos['status']['architecture'])}',
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

	def update_splayd_infos
		@row = $db[:splayds].first(:id=>@id)
	end

	def localize
		if @row.get(:ip) and
				not @row.get(:ip) == "127.0.0.1" and
				not @row.get(:ip) =~ /192\.168\..*/ and
				not @row.get(:ip) =~ /10\.0\..*/

			$log.debug("Trying to localize: #{@row.get(:ip)}")
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
						"#{loc.country_code2.downcase} #{loc.city_name}")
				$db.do "UPDATE splayds SET
						hostname='#{hostname}',
						country='#{loc.country_code2.downcase}',
						city='#{loc.city_name}',
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
		$log.debug("next action to do: #{action}")
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
