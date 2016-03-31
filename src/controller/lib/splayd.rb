#$db = DBUtils.get_new_mysql_sequel
# $new_db = DBUtils.get_new_mysql

class Splayd

  attr_accessor :row
  attr_reader :id
  
  @@transaction_mutex = Mutex.new
  @@unseen_timeout = 3600
  @@auto_add = SplayControllerConfig::AutoAddSplayds
  @row = nil #a pointer to the row in the database for this splayd
  
  def initialize(id)
    @row = $db.from(:splayds)[:id => id]
    if not @row
      @row = $db.from(:splayds)[:key => id]
    end
    if not @row and @@auto_add
      $db.from(:splayds).insert(:key => id)
      @row = $db.from(:splayds)[:key => id]
    end
    if @row then
      @id = @row[:id]
    end
    $log.info("Splayd with ID #{@id} initialized")
  end
  
  def self.init
    $db.from(:splayds).where("status = 'AVAILABLE' OR status = 'PREAVAILABLE'").update(:status => 'UNAVAILABLE')
    Splayd.reset_actions
    Splayd.reset_unseen
  end

  def self.reset_unseen
    $db.from(:splayds).where("last_contact_time < ? AND ( status = 'AVAILABLE' OR status = 'UNAVAILABLE' OR status = 'PREAVAILABLE')", Time.now.to_i - @@unseen_timeout).each do |splayd|
#    $db.do "SELECT * FROM splayds WHERE
#  		last_contact_time<'#{Time.now.to_i - @@unseen_timeout}' AND
#  		(status='AVAILABLE' OR
#  		status='UNAVAILABLE' OR
#  		status='PREAVAILABLE')" do |splayd|
      $log.debug("Splayd #{splayd[:id]} (#{splayd[:ip]} - #{splayd[:status]}) not seen " +
        "since #{@@unseen_timeout} seconds (#{splayd[:last_contact_time]}) => RESET")
      # We kill the thread if there is one
      s = Splayd.new(splayd[:id])
      s.kill
      s.reset
    end
  end

  def self.reset_actions
    # When the controller start, if some actions where send but still not
    # replied, we will never receive the reply so we set the action to the
    # FAILURE status.
    #$db.do "UPDATE actions SET status='FAILURE' WHERE status='SENDING'"
    $db.from(:actions).where("status = 'SENDING'").update(:status => 'FAILURE')
    #[:actions].where(:status=>'SENDING').update(:status=>'FAILURE')
    # Uncomplete actions, jobd should put the again.
    $db.from(:actions).where("status = 'TEMP'").delete
    #[:actions].where(:status=>'TEMP').delete #$db.do "DELETE FROM actions WHERE status='TEMP'"
  end
  
  def self.gen_session
    return OpenSSL::Digest::MD5.hexdigest(rand(1000000).to_s + "session" + rand(1000000).to_s)
  end
  	
  def self.has_job(splayd_id, job_id)
    sj = $db.from(:splayd_jobs).where('splayd_id = ? AND job_id = ?', splayd_id, job_id).first
    #.fetch "SELECT * FROM splayd_jobs
    #		WHERE splayd_jobs.splayd_id='#{splayd_id}' AND
    #		splayd_jobs.job_id='#{job_id}'"
    if sj then return true else return false end
  end

  # Send an action to a splayd only if it is active.
  # For performance reasons, we will not check anymore the availability because
  # 99.9% of time, when an action is sent, the splayd is available. This should
  # have no consequences (other than a little DB space) because when the splayd
  # comes back from a reset state, it will be reset() and the commands deleted.
  def self.add_action(splayd_id, job_id, command, data = '')
    $db.from(:actions).insert(:splayd_id => splayd_id, :job_id => job_id, :command => command, :data => addslashes(data))
    # .do "INSERT INTO actions SET
    # 		splayd_id='#{splayd_id}',
    # 		job_id='#{job_id}',
    # 		command='#{command}',
    # 		data='#{addslashes data}'"
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
    $db.from(:blacklist_hosts).each do |row|
    #[:blacklist_hosts].select(:host) do |row| #.select_all "SELECT host FROM blacklist_hosts"
    	hosts << row[:id]
    end
    return hosts
  end
  
  def self.localize_all
    return Thread.new do
      $db.from(:splayds).each do |s| #.select_all "SELECT id FROM splayds"
      	splayd = Splayd.new(s[:id])
      	splayd.localize
      end
    end
  end
  
  def to_s
  	if @row[:name] and @row[:ip]
  		return "#{@id} (#{@row[:name]}, #{@row[:ip]})"
  	elsif @row[:ip]
  		return "#{@id} (#{@row[:ip]})"
  	else
  		return "#{@id}"
  	end
  end
  
  def check_and_set_preavailable
    r = false
    # to protect the $db object while in use.
    @@transaction_mutex.synchronize do
      $db.transaction do
        status = $db.from(:splayds).where('id = ?', @id)[:status]
        puts "STATUS"
        puts status
        #[:splayds].where(:id=>@id).get(:status)
          if status == 'REGISTERED' or status == 'UNAVAILABLE' or status == 'RESET' then
            $db.from(:splayds).where('id = ?', @id).update(:status =>'PREAVAILABLE')
            #.do "UPDATE splayds SET status='PREAVAILABLE' WHERE id ='#{@id}'"
            r = true
          end
        end # COMMIT issued only here
    end
    return r
  end

  # Check that this IP is not used by another splayd.
  def ip_check ip
    query = $db.from(:splayds).where("ip = ? AND key != ? AND (status='AVAILABLE' OR status='UNAVAILABLE' OR status='PREAVAILABLE')", ip, @row[:key]).first
    if ip == "127.0.0.1" or ip=="::ffff:127.0.0.1" or not query
      #$db.fetch "SELECT * FROM splayds WHERE
      #ip='#{ip}' AND
      #`key`!='#{@row.get(:key)}' AND
      #(status='AVAILABLE' OR status='UNAVAILABLE' OR status='PREAVAILABLE')"
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
    $db.from(:splayds).where('id = ?', @id).update(
      :name                       =>  addslashes(infos['settings']['name']),
      :version                    =>  addslashes(infos['status']['version']),
      :protocol                   =>  addslashes(infos['settings']['protocol']),
      :lua_version                =>  addslashes(infos['status']['lua_version']),
      :bits                       =>  addslashes(infos['status']['bits']),
      :endianness                 =>  addslashes(infos['status']['endianness']),
      :os                         =>  addslashes(infos['status']['os']),
      :full_os                    =>  addslashes(infos['status']['full_os']),
      :architecture               =>  addslashes(infos['status']['architecture']),
      :start_time                 =>  addslashes((Time.now.to_f - infos['status']['uptime'].to_f).to_i),
      :max_number                 =>  addslashes(infos['settings']['job']['max_number']),
      :max_mem                    =>  addslashes(infos['settings']['job']['max_mem']),
      :disk_max_size              =>  addslashes(infos['settings']['job']['disk']['max_size']),
      :disk_max_files             =>  addslashes(infos['settings']['job']['disk']['max_files']),
      :disk_max_file_descriptors  =>  addslashes(infos['settings']['job']['disk']['max_file_descriptors']),
      :network_max_send           =>  addslashes(infos['settings']['job']['network']['max_send']),
      :network_max_receive        =>  addslashes(infos['settings']['job']['network']['max_receive']),
      :network_max_sockets        =>  addslashes(infos['settings']['job']['network']['max_sockets']),
      :network_max_ports          =>  addslashes(infos['settings']['job']['network']['max_ports']),
      :network_send_speed         =>  addslashes(infos['settings']['network']['send_speed']),
      :network_receive_speed      =>  addslashes(infos['settings']['network']['receive_speed'])
    )
    #$db.do "UPDATE splayds SET
    #name='#{addslashes(infos['settings']['name'])}',
    #version='#{addslashes(infos['status']['version'])}',
    #protocol='#{addslashes(infos['settings']['protocol'])}',
    #lua_version='#{addslashes(infos['status']['lua_version'])}',
    #bits='#{addslashes(infos['status']['bits'])}',
    #endianness='#{addslashes(infos['status']['endianness'])}',
    #os='#{addslashes(infos['status']['os'])}',
    #full_os='#{addslashes(infos['status']['full_os'])}',
    #architecture='#{addslashes(infos['status']['architecture'])}',
    #start_time='#{addslashes((Time.now.to_f - infos['status']['uptime'].to_f).to_i)}',
    #max_number='#{addslashes(infos['settings']['job']['max_number'])}',
    #max_mem='#{addslashes(infos['settings']['job']['max_mem'])}',
    #disk_max_size='#{addslashes(infos['settings']['job']['disk']['max_size'])}',
    #disk_max_files='#{addslashes(infos['settings']['job']['disk']['max_files'])}',
    #disk_max_file_descriptors='#{addslashes(infos['settings']['job']['disk']['max_file_descriptors'])}',
    #network_max_send='#{addslashes(infos['settings']['job']['network']['max_send'])}',
    #network_max_receive='#{addslashes(infos['settings']['job']['network']['max_receive'])}',
    #network_max_sockets='#{addslashes(infos['settings']['job']['network']['max_sockets'])}',
    #network_max_ports='#{addslashes(infos['settings']['job']['network']['max_ports'])}',
    #network_send_speed='#{addslashes(infos['settings']['network']['send_speed'])}',
    #network_receive_speed='#{addslashes(infos['settings']['network']['receive_speed'])}'
    #WHERE id='#{@id}'"
    parse_loadavg(infos['status']['loadavg'])
  end

  def update_splayd_infos
    @row = $db.from(:splayds)[:id => @id]
  end

  def localize
    if @row[:ip] and not @row[:ip] == "127.0.0.1" and not @row[:ip] =~ /192\.168\..*/ and 
      not @row[:ip] =~ /10\.0\..*/

      $log.debug("Trying to localize: #{@row[:ip]}")
      begin
    	hostname = ""
    	begin
    	  Timeout::timeout(10, StandardError) do hostname = Resolv::getname(@row[:ip]) end
    	rescue
    	  $log.warn("Timeout resolving hostname of IP: #{@row[:ip]}")
    	end
    	loc = Localization.get(@row[:ip])
    	$log.info("#{@id} #{@row[:ip]} #{hostname} " + "#{loc.country_code2.downcase} #{loc.city_name}")
    	$db.from(:splayds).where('id = ?', @id).update(
          :hostname =>hostname,
          :country  =>loc.country_code2.downcase,
          :city     =>loc.city_name,
          :latitude =>loc.latitude,
          :longitude=>loc.longitude
        )
        #do "UPDATE splayds SET
        #hostname='#{hostname}',
        #country='#{loc.country_code2.downcase}',
        #city='#{loc.city_name}',
        #latitude='#{loc.latitude}',
        #longitude='#{loc.longitude}'
        #WHERE id='#{@id}'"
        rescue => e
          puts e
    	  $log.error("Impossible localization of #{@row[:ip]}")
      end
    end
  end

  def remove_action action
    $db.from(:actions).where('id = ?', action[:id]).delete
    #.do "DELETE FROM actions WHERE id='#{action['id']}'"
  end

  def update(field, value)
    $db.from(:splayds).where('id = ?', @id).update(field.to_sym => value)
    #do "UPDATE splayds SET #{field}='#{value}' WHERE id='#{@id[:id]}'"
    @row[field.to_sym] = value
  end

  def kill
    puts "When kill is called check ID type: #{@id}"
    if SplaydServer.threads[@id]
      SplaydServer.threads.delete(@id).kill
    end
  end

	# DB cleaning when a splayd is reset.
  def reset
    session = Splayd.gen_session
    #@row['session'] = Splayd.gen_session
    $db.from(:splayds).where('id = ?', @id).update(:status => 'RESET', :session => session)
#    .do "UPDATE splayds SET
#    		status='RESET', session='#{session}' WHERE id='#{@id[:id]}'"
    
    $db.from(:actions).where('splayd_id = ?', @id).delete
    $db.from(:splayd_jobs).where('splayd_id = ?', @id).delete
    #do "DELETE FROM actions WHERE splayd_id='#{@id[:id]}'"
    #$db.do "DELETE FROM splayd_jobs WHERE splayd_id='#{@id[:id]}'"
    $db.from(:splayd_availabilities).insert(:splayd_id => @id, :status => 'RESET', :time => Time.now.to_i)
    #$db.do "INSERT INTO splayd_availabilities SET
    #	  splayd_id='#{@id[:id]}', status='RESET', time='#{Time.now.to_i}'"
    # for trace job
    $db.from(:splayd_selections).where('splayd_id = ?', @id).update(:reset => 'TRUE')
    #.do "UPDATE splayd_selections SET reset='TRUE' WHERE splayd_id='#{@id[:id]}'"
  end

  def unavailable
  	$db.from(:splayds).where('id = ?', @id).update(:status => 'UNAVAILABLE')
        #do "UPDATE splayds SET status='UNAVAILABLE' WHERE id='#{@id[:id]}'"
  	$db.from(:splayd_availabilities).insert(
          :splayd_id => @id,
  	  :status    => 'UNAVAILABLE',
  	  :time      => Time.now.to_i
        )
        #.do "INSERT INTO splayd_availabilities SET
        #  		   splayd_id='#{@id[:id]}',
        #  		   status='UNAVAILABLE',
        #  		   time='#{Time.now.to_i}'"
  end

  def action_failure
    $db.from(:actions).where("status ='SENDING' AND splayd_id = ?", @id).update(:status => 'FAILURE')
#    do "UPDATE actions SET status='FAILURE'
#    		WHERE status='SENDING' AND splayd_id='#{@id[:id]}'"
  end

  def available
  	$db.from(:splayds).where('id = ?', @id).update(:status => 'AVAILABLE')
        #do "UPDATE splayds SET status='AVAILABLE' WHERE id='#{@id[:id]}'"
  	$db.from(:splayd_availabilities).insert(
            :splayd_id=> @id,
  	    :ip       => @row[:ip],
  	    :status   => 'AVAILABLE',
  	    :time     => Time.now.to_i
        )
        #do "INSERT INTO splayd_availabilities SET
        #  		   splayd_id='#{@id[:id]}',
        #  		   ip='#{@row['ip']}',
        #  		   status='AVAILABLE',
        #  		   time='#{Time.now.to_i}'"
  	last_contact
  	restore_actions
  end

  def last_contact
  	t = Time.now.to_i
        $db.from(:splayds).where('id = ?', @id).update(:last_contact_time => t)
        #do "UPDATE splayds SET
  	#	   last_contact_time='#{Time.now.to_i}' WHERE id='#{@id[:id]}'"
  	return t
  end

  # Restore actions in failure state.
  def restore_actions
    $log.info($db)
    $db.from(:actions).where("status = 'FAILURE' AND splayd_id = ?", @id).each do |action|
      #do "SELECT * FROM actions WHERE status='FAILURE' AND splayd_id='#{@id[:id]}'" do |action|
      if action[:command] == 'REGISTER'
        # We should put the FREE-REGISTER at the same place
        # where REGISTER was. But, no other register action concerning
        # this splayd and this job can exists (because registering is
        # split into states), so, if we remove the REGISTER, we can safely
        # add the FREE-REGISTER commands at the top of the
        # actions.
        job = $db.from(:jobs).where('id = ?', action[:job_id]).first
        #.select_one "SELECT ref FROM jobs WHERE id='#{action['job_id']}'"
        $db.from(:actions).where('id = ?', action[:id]).delete
        #do "DELETE FROM actions WHERE id='#{action['id']}'"
        Splayd.add_action(action[:splayd_id], action[:job_id], 'FREE', job[:ref])
        Splayd.add_action(action[:splayd_id], action[:job_id], 'REGISTER', addslashes(job[:code]))
      else
        $db.from(:actions).where('id = ?', action[:id]).update(:status => 'WAITING')
        #do "UPDATE actions SET status='WAITING' WHERE id='#{action['id']}'"
      end
    end
  end

  # Return the next WAITING action and set status to SENDING.
  def next_action
    resu = nil
    $db["SELECT * FROM actions WHERE splayd_id='#{@id}' ORDER BY id"].each do |action|
      $log.info("next action to do: #{action[:id]} - #{action[:command]}")
      if action[:status] == 'TEMP'
      	$log.info("INCOMPLETE ACTION: #{action[:command]} " + "(splayd: #{@id}, job: #{action[:job_id]})")
      end
      if action[:status] == 'WAITING'
        $db.from(:actions).where('id = ?', action[:id]).update(:status => 'SENDING')
          #do "UPDATE actions SET
        #		status='SENDING'
        #		WHERE id='#{action['id']}'"
        resu = action
        break
      end
    end
    return resu
  end

  def s_j_register job_id
    $db.from(:splayd_jobs).where("splayd_id = ? AND job_id = ? AND status='RESERVED'", @id, job_id).update(:status => 'WAITING')
  end

  def s_j_free job_id
    $db.from(:splayd_jobs).where('splayd_id = ? AND job_id = ?', @id, job_id).delete
  end

  def s_j_start job_id
    $db.from(:splayd_jobs).where('splayd_id = ? AND job_id = ?', @id, job_id).update(:status => 'RUNNING')
  end

  def s_j_stop job_id
    $db.from(:splayd_jobs).where('splayd_id = ? AND job_id = ?', @id, job_id).update(:status => 'WAITING')
  end

  def s_j_status data
    data = JSON.parse data
    puts "Data content: #{data}"
    $db.from(:splayd_jobs).where("status != 'RESERVED' AND splayd_id = ?", @id).each do |sj|
      #  select_all "SELECT * FROM splayd_jobs WHERE
      #  		splayd_id='#{@id}' AND
      #  		status!='RESERVED'" do |sj|
      job = $db.from(:jobs).where('id = ?', sj[:job_id]).first
      # There is no difference in Lua between Hash and Array, so when it's
      # empty (an Hash), we encoded it like an empy Array.
      if data['jobs'].class == Hash and data['jobs'][job[:ref]]
      	if data['jobs'][job[:ref]]['status'] == "waiting"
            $db.from(:splayd_jobs).where('id = ?', sj[:id]).update(:status => 'WAITING')
            #  do "UPDATE splayd_jobs SET status='WAITING'
            #		WHERE id='#{sj['id']}'"
      	end
      	# NOTE normally no needed because already set to RUNNING when
      	# we send the START command.
      	if data['jobs'][job[:ref]]['status'] == "running"
            $db.from(:splayd_jobs).where('id = ?', sj[:id]).update(:status => 'RUNNING')
            #do "UPDATE splayd_jobs SET status='RUNNING'
            #		WHERE id='#{sj['id']}'"
      	end
      else
        $db.from(:splayd_jobs).where('id = ?', sj[:id]).delete
        #$db.do "DELETE FROM splayd_jobs WHERE id='#{sj['id']}'"
      end
      # it can't be new jobs in data['jobs'] that don't have already an
      # entry in splayd_jobs
    end
  end

  def parse_loadavg s
    if s.strip != ""
    	l = s.split(" ")
    	$db.from(:splayds).where('id = ?', @id).update(:load_1 => l[0], :load_5 => l[1], :load_15 => l[2])
        #do "UPDATE splayds SET
    	#		load_1='#{l[0]}',
    	#		load_5='#{l[1]}',
    	#		load_15='#{l[2]}'
    	#		WHERE id='#{@id}'"
    else
    	# NOTE should too be fixed in splayd
    	$log.warn("Splayd #{@id} report an empty loadavg. ")
    	$db.from(:splayds).where('id = ?', @id).update(:load_1 => '10', :load_5 => '10', :load_15 => '10')
        #$db.do "UPDATE splayds SET
    	#		load_1='10',
    	#		load_5='10',
    	#		load_15='10'
    	#		WHERE id='#{@id}'"
    end
  end
  
  # NOTE then corresponding entry may already have been deleted if the reply
  # comes after the job has finished his registration, but no problem.
  def s_sel_reply(job_id, port, reply_time)
    $db.from(:splayd_selections).where('splayd_id = ? AND job_id = ?', @id, job_id).update(
      :replied => 'TRUE', :reply_time => reply_time, :port => port
    )
    #do "UPDATE splayd_selections SET
    #  			replied='TRUE',
    #  			reply_time='#{reply_time}',
    #  			port='#{port}'
    #  			WHERE splayd_id='#{@id}' AND job_id='#{job_id}'"
  end

end
