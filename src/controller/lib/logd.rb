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
require 'net/ping' #ping the jobd to compute the RTT
include Net
class LogdServer

	@@log_max_size = SplayControllerConfig::LogMaxSize
	@@log_dir = SplayControllerConfig::LogDir
	@@nat_gateway_ip = SplayControllerConfig::NATGatewayIP

	def initialize(port = nil)
		@port = port || SplayControllerConfig::LogdPort
	end

	def run
		return Thread.new() do
			main
		end
	end

	def main
		begin
			$log.info(">>> Splay Controller Log Daemon (port: #{@port})")
      
			if not File.exists? File.expand_path(@@log_dir)
				if not FileUtils::mkdir @@log_dir
					$log.warn("Cannot create log dir: #{@@log_dir}")
				end
			end

			$log.debug("Job logs will be written into #{@@log_dir}")

			server = TCPServer.new(@port)
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			return
		end

		$log.info("Waiting for job's log on port: #{@port}")

		begin
			loop do
				socket = server.accept
				ip = socket.peeraddr[3]
    		$log.debug("Logd received connection from #{ip}")
        
				# We check that this IP is of one of our splayd (initial security
				# check)

				# TODO make a static function in Splayd.
				splayd = $db.fetch "SELECT id FROM splayds WHERE
						(status='AVAILABLE' OR status='UNAVAILABLE') AND
						ip='#{ip}'"

				if splayd or (@@nat_gateway_ip and ip == @@nat_gateway_ip)
					Logd.new(socket).run
				else
					$log.info("Unknown IP (#{ip}) trying to log...")
					begin socket.close; rescue; end
				end
			end
		rescue => e
			$log.error(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			sleep 1
			retry
		end
	end
end

class Logd

	@@log_max_size = SplayControllerConfig::LogMaxSize
	@@log_dir = SplayControllerConfig::LogDir
	@@nat_gateway_ip = SplayControllerConfig::NATGatewayIP
  @@use_splayd_timestamps = SplayControllerConfig::UseSplaydTimestamps
	def initialize(so)
		@so = so
	end

  def prefix_ctrl(job)
      ts = Time.now
      pfix = ts.strftime("%Y-%m-%d %H:%M:%S") << ".#{ts.usec} " << "(#{job['splayd_id']}) "            
  		return pfix
  end
  
  def prefix(job,ts=nil)
  		#t = Time.now
  		if ts==nil then ts=Time.now end
      pfix = ts.strftime("%Y-%m-%d %H:%M:%S") << ".#{ts.usec} " << "(#{job['splayd_id']}) "            
  		return pfix
  end
	
  def extract_timestamp_msg(raw_msg)
    if raw_msg == nil then 
      ts = Time.now
      msg= "Error receiving message"
      return ts,msg
    end
  	  $log.debug("Parsing raw message: #{raw_msg}")
      toks=raw_msg.split(" ")
      ts=Time.at(toks[0].to_i,toks[1].to_i)
      msg=raw_msg[ toks[0].size + toks[1].size + 1 , raw_msg.size]
      return ts,msg
  end
    #shift the timestamp wrt to the clock shift with the controller, remove the RTT as well. 
  def adjust_ts(ts,diff,rtt)
      ts = ts - diff - rtt
  end

	def run
		Thread.new do
			begin
				$log.debug("Log client accepted.")
				ip = @so.peeraddr[3]
				# TODO replace
				#@so.set_timeout 60

				job_ref = @so.gets.chop

				# permit to identify splayds running on a same IP (local test) or behing
				# a NAT (same visible IP)
				splayd_session = @so.gets.chop

				if @@nat_gateway_ip and ip == @@nat_gateway_ip
					job = $db.fetch "SELECT
							jobs.id, splayds.id AS splayd_id, splayds.ip AS splayd_ip
							FROM splayds, splayd_selections, jobs WHERE
							jobs.ref='#{job_ref}' AND
							jobs.status='RUNNING' AND
							splayds.session='#{splayd_session}' AND
							splayd_selections.job_id=jobs.id AND
							splayd_selections.splayd_id=splayds.id"
				else
					# We verify that the job exists and runs on a splayd that have this IP.
					job = $db.fetch "SELECT
							jobs.id, splayds.id AS splayd_id, splayds.ip AS splayd_ip
							FROM splayds, splayd_selections, jobs WHERE
							jobs.ref='#{job_ref}' AND
							jobs.status='RUNNING' AND
							splayds.ip='#{ip}' AND
							splayds.session='#{splayd_session}' AND
							splayd_selections.job_id=jobs.id AND
							splayd_selections.splayd_id=splayds.id"
				end
        
        
        jobd_localtime = @so.gets.chop
        
        #Ping2::TCP.service_check = true #prevents false negatives, the host is UP for sure.
        p1 = Net::Ping::TCP.new(:host => ip)
        t0= Time.now
        p1.ping #do the ping
        rtt = (Time.now - t0)/2
        
        ctrl_time = Time.now
        t= jobd_localtime.split(".")
        jt=Time.at(t[0].to_i,t[1].to_i)        
        difftime = ctrl_time - jt
        $log.info("Splayd (#{job['splayd_id']}) remote-time before job: #{jt.strftime("%H:%M:%S")}.#{jt.usec.to_s} DIFF: #{difftime} RTT: #{rtt}")
        
         adjust_ts(jt,difftime,rtt)
        $log.debug("Logd retrieved job ref #{job_ref}")
				if job
					# TODO replace
					#@so.set_timeout(24 * 3600)
					fname = "#{@@log_dir}/#{job['id']}"
					count = 0
          last_ts=nil
					begin
#             file = File.open(fname, File::WRONLY|File::APPEND|File::CREAT, 0666) 
						file = File.new(fname, File::WRONLY|File::APPEND|File::CREAT, 0777) 
            # http://ruby-doc.org/core-1.8.7/IO.html#method-i-sync
            # This affects future operations and causes output to be written without block buffering.
            file.sync = true

						file.flock File::LOCK_EX # synchro between processes
            if (@@use_splayd_timestamps==true) then 
              file.puts "#{prefix(job,jt)} START_LOG"
            else
            	file.puts "#{prefix_ctrl(job)} START_LOG" 
            end
						file.flock File::LOCK_UN
						loop do
							msg = nil
							begin
							  raw=@so.gets
                if raw.nil? then break end
                msg = raw.chop  #when socket is closed abruptly
            	rescue
								# normal when the client stop logging or max reached
								break
							end

							if msg then #prevents from errors when msg=nil, this can happen if raw=nil
								count = count + msg.length
                ts,m = extract_timestamp_msg(msg)
                adjust_ts(ts,difftime,rtt)
								file.flock File::LOCK_EX # synchro between processes
                if (@@use_splayd_timestamps==true) then 
                  file.puts prefix(job,ts) << " " << m
                else
                  file.puts prefix_ctrl(job) << " " << m                
                end
								file.flock File::LOCK_UN
                last_ts=ts
							end

							if count > @@log_max_size then 
                $log.info("Log too big: #{count}, log_max_size: #{@@log_max_size}")
                  break 
              end
						end

						file.flock File::LOCK_EX # synchro between processes
            if (@@use_splayd_timestamps==true) then 
                now  = Time.now
          		  elap = now - last_ts
          			end_log_ts = now - elap - difftime
          			file.puts "#{prefix(job,end_log_ts)} END_LOG"
            else
          	    file.puts "#{prefix_ctrl(job)} END_LOG"
            end
						file.flock File::LOCK_UN
					ensure
						begin
							file.close
						rescue
						end
					end
				else
					$log.warn("The job #{job_ref} doesn't exists on #{ip} (or just killed)")
				end
			rescue => e
				$log.error(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			ensure
				begin
					@so.close
				rescue
				end
			end
		end
	end
end

