## Splay Controller ### v1.2 ###
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


# NOTE
# When we try to select splayds for a job, the only case that could require a
# synchro is that a splayd can have more new free slots than what we have check
# (because a slot can be freed during the select phase). But that is never a
# problem ! So no locks are needed.

class JobdStandard < Jobd

	@@scheduler = 'standard'

	# LOCAL => REGISTERING|NO RESSOURCES|QUEUED
	def self.status_local
		@@dlock_jr.get

		c_splayd = nil

		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='LOCAL'" do |job|
		
			# Splayds selection
			c_splayd, occupation, nb_selected_splayds, new_job, do_next = Jobd.status_local_common(job)	

			# If this job cannot be submitted immediately, jump to the next one
			if do_next == true
				next
			end	

			q_sel = ""
			q_job = ""
			q_act = ""

			count = 0
			occupation.sort {|a, b| a[1] <=> b[1]}
			occupation.each do |splayd_id, occ|
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"
	
				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1

				count += 1
				if count >= nb_selected_splayds then break end
			end

			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|

				splay_id = mm['splayd_id']
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"

				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
			end

			q_sel = q_sel[0, q_sel.length - 1]
			q_job = q_job[0, q_job.length - 1]
			q_act = q_act[0, q_act.length - 1]
			$db.do "INSERT INTO splayd_selections (splayd_id, job_id) VALUES #{q_sel}"
			$db.do "INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}"

			$db.do "INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}"
			$db.do "UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
					WHERE job_id='#{job['id']}' AND command='REGISTER' AND status='TEMP'"

			set_job_status(job['id'], 'REGISTERING')
		end
		@@dlock_jr.release
	end

	# REGISTERING => REGISTERING_TIMEOUT|RUNNING
	def self.status_registering
		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='REGISTERING'" do |job|

			# Mandatory filter
			mandatory_filter = ''
			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|
				mandatory_filter += " AND splayd_id!=#{mm['splayd_id']} "
			end

			# NOTE ORDER BY reply_time can not be an excellent idea in that sense that
			# it could advantage splayd near of the controller.
			selected_splayds = []
			$db.select_all "SELECT splayd_id FROM splayd_selections WHERE
					job_id='#{job['id']}' AND
					replied='TRUE'
					#{mandatory_filter}
					ORDER BY reply_time LIMIT #{job['nb_splayds']}" do |m|
				selected_splayds << m['splayd_id']
			end

			# check if enough splayds have responded
			normal_ok = selected_splayds.size == job['nb_splayds']

			mandatory_ok = true

			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|
				if not $db.select_one "SELECT id FROM splayd_selections WHERE
						splayd_id='#{mm['splayd_id']}' AND
						job_id='#{job['id']}' AND
						replied='TRUE'"
					mandatory_ok = false
					break
				end
			end
			
			if normal_ok and mandatory_ok

				selected_splayds.each do |splayd_id|
					$db.do("UPDATE splayd_selections SET
							selected='TRUE'
							WHERE
							splayd_id='#{splayd_id}' AND
							job_id='#{job['id']}'")
				end
				$db.select_all "SELECT * FROM job_mandatory_splayds
						WHERE job_id='#{job['id']}'" do |mm|

					$db.do("UPDATE splayd_selections SET
							selected='TRUE'
							WHERE
							splayd_id='#{mm['splayd_id']}' AND
							job_id='#{job['id']}'")
				end

				# We need to unregister the job on the non selected splayds.
				q_act = ""
				$db.select_all "SELECT * FROM splayd_selections WHERE
						job_id='#{job['id']}' AND
						selected='FALSE'" do |m_s|
					q_act = q_act + "('#{m_s['splayd_id']}','#{job['id']}','FREE', '#{job['ref']}'),"
				end
				if q_act != ""
					q_act = q_act[0, q_act.length - 1]
					$db.do "INSERT INTO actions (splayd_id, job_id, command, data) VALUES #{q_act}"
				end

				send_all_list(job, "SELECT * FROM splayd_selections WHERE
						job_id='#{job['id']}' AND selected='TRUE'")

				# We change it before sending the START commands because it
				# seems more consistant... We had problem with first jobs
				# begining to log before the status change was done and refused
				# by the log server.
				set_job_status(job['id'], 'RUNNING')

				# Create a symlink to the log dir
				File.symlink("#{@@log_dir}/#{job['id']}", "#{@@link_log_dir}/#{job['ref']}.txt")

				send_start(job, "SELECT * FROM splayd_selections WHERE
						job_id='#{job['id']}' AND selected='TRUE'")

			else
				Jobd.status_registering_common(job)
			end
		end
	end

	# RUNNING => ENDED
	def self.status_running
		$db.select_all "SELECT * FROM jobs WHERE
		  scheduler='#{@@scheduler}' AND status='RUNNING'" do |job|
			if not $db.select_one "SELECT * FROM splayd_jobs
				WHERE job_id='#{job['id']}' AND status!='RESERVED'"
				set_job_status(job['id'], 'ENDED')
			end
		end
	end

  	# QUEUED => REGISTERING | QUEUED | NO_RESSOURCES
  	def self.status_queued
    		@@dlock_jr.get

    		c_splayd = nil

    		$db.select_all "SELECT * FROM jobs WHERE
	            		scheduler='#{@@scheduler}' AND status='QUEUED' AND (scheduled_at is NULL OR scheduled_at<NOW())" do |job|

			
			# Splayds selection
			c_splayd, occupation, nb_selected_splayds, new_job, do_next = Jobd.status_queued_common(job)	

			# If this job cannot be submitted immediately, jump to the next one
			if do_next == true
				next
			end	
		
			q_sel = ""
			q_job = ""
			q_act = ""

			count = 0
			occupation.sort {|a, b| a[1] <=> b[1]}
			occupation.each do |splayd_id, occ|
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"

				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1

				count += 1
				if count >= nb_selected_splayds then break end
			end

			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|

				splay_id = mm['splayd_id']
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"

				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
			end

			q_sel = q_sel[0, q_sel.length - 1]
			q_job = q_job[0, q_job.length - 1]
			q_act = q_act[0, q_act.length - 1]
			$db.do "INSERT INTO splayd_selections (splayd_id, job_id) VALUES #{q_sel}"
			$db.do "INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}"

			$db.do "INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}"
			$db.do "UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
					WHERE job_id='#{job['id']}' AND command='REGISTER' AND status='TEMP'"

			set_job_status(job['id'], 'REGISTERING')

   		end
    		@@dlock_jr.release
  	end
			
	def self.kill_job(job, status_msg = '')
  		$log.info("KILLING #{job['id']}")
		Jobd.status_killed_common(job, status_msg)
	end

	def self.command
		# NOTE splayd_jobs table is cleaned directly by splayd when it apply the
		# free command (or reset)
		$db.select_all "SELECT * FROM jobs WHERE scheduler='#{@@scheduler}' AND
				command IS NOT NULL" do |job|
			if job['command'] =~ /kill|KILL/
				kill_job(job, "user kill")
			else
				msg = "Not understood command: #{job['command']}"
				$db.do "UPDATE jobs SET command_msg='#{msg}' WHERE id='#{job['id']}'"
			end
			$db.do "UPDATE jobs SET command='' WHERE id='#{job['id']}'"
		end
	end

	# KILL AT
	def self.kill_max_time
		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND
				status='RUNNING' AND
				max_time IS NOT NULL AND
				status_time + max_time < #{Time.now.to_i}" do |job|
			kill_job(job, "max execution time")
		end
	end

end
