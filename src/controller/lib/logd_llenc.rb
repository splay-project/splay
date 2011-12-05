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

			if not File.exists? @@log_dir
				if not FileUtils::mkdir @@log_dir
					$log.warn("Cannot create log dir: #{@@log_dir}")
				end
			end

			$log.debug("Logging into #{@@log_dir}")

			server = TCPserver.new(@port)
		rescue => e
			$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			return
		end

		$log.debug("Waiting for job's log on port: #{@port}")

		begin
			loop do
				socket = server.accept
				ip = socket.peeraddr[3]

				# We check that this IP is of one of our splayd (initial security
				# check)

				# TODO make a static function in Splayd.
				splayd = $db.select_one "SELECT id FROM splayds WHERE
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

	def initialize(so)
		@so = so
	end

	def run
		Thread.new do
			begin
				$log.debug("Log client accepted.")
				ip = @so.peeraddr[3]
				ll_so = LLenc.new @so
				ll_so.set_timeout 60

				job_ref = ll_so.read

				# permit to identify splayds running on a same IP (local test) or behing
				# a NAT (same visible IP)
				splayd_session = ll_so.read

				if @@nat_gateway_ip and ip == @@nat_gateway_ip
					job = $db.select_one "SELECT
							jobs.id, splayds.id AS splayd_id, splayds.ip AS splayd_ip
							FROM splayds, splayd_selections, jobs WHERE
							jobs.ref='#{job_ref}' AND
							jobs.status='RUNNING' AND
							splayds.session='#{splayd_session}' AND
							splayd_selections.job_id=jobs.id AND
							splayd_selections.splayd_id=splayds.id"
				else
					# We verify that the job exists and runs on a splayd that have this IP.
					job = $db.select_one "SELECT
							jobs.id, splayds.id AS splayd_id, splayds.ip AS splayd_ip
							FROM splayds, splayd_selections, jobs WHERE
							jobs.ref='#{job_ref}' AND
							jobs.status='RUNNING' AND
							splayds.ip='#{ip}' AND
							splayds.session='#{splayd_session}' AND
							splayd_selections.job_id=jobs.id AND
							splayd_selections.splayd_id=splayds.id"
				end

				if job
					ll_so.set_timeout(24 * 3600)
					fname = "#{@@log_dir}/#{job['id']}"
					count = 0
					begin
#             file = File.open(fname, File::WRONLY|File::APPEND|File::CREAT, 0666) 
						file = File.new(fname, File::WRONLY|File::APPEND|File::CREAT, 0777) 
						file.sync = true
						loop do
							msg = nil
							begin
								msg = ll_so.read(@@log_max_size - count)
							rescue
								# normal when the client stop logging or max reached
								break
							end
							
							# OLD
							#pfix = "#{Time.now.strftime("%H:%M:%S")} - " +
									#"#{job['splayd_id']} - #{job['splayd_ip']}"

							# SHORT unix
							#pfix = "#{Time.now.to_f} " +
									#"#{job['splayd_id']} ="
							
							#t = Time.now
							#ms = (t.to_f - t.to_i).to_s[1,3]
							#pfix = "#{t.strftime("%H:%M:%S")}#{ms} " +
									#"#{job['splayd_id']} #{job['splayd_ip']} ="

							t = Time.now
							ms = (t.to_f - t.to_i).to_s[1,3]
							pfix = "#{t.strftime("%H:%M:%S")}#{ms} " +
									"(#{job['splayd_id']}) "

							count = count + msg.length
							file.flock File::LOCK_EX # synchro between processes
							file.puts "#{pfix} #{msg}"
							file.flock File::LOCK_UN
						end
						t = Time.now
						ms = (t.to_f - t.to_i).to_s[1,3]
						pfix = "#{t.strftime("%H:%M:%S")}#{ms} " +
								"(#{job['splayd_id']}) "

						file.flock File::LOCK_EX # synchro between processes
						file.puts "#{pfix} end_log (connection lost/closed/max_size)"
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

