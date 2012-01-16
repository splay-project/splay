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


# NOTE
# When we try to select splayds for a job, the only case that could require a
# synchro is that a splayd can have more new free slots than what we have check
# (because a slot can be freed during the select phase). But that is never a
# problem ! So no locks are needed.

class JobdTraceAlt < Jobd

	@@scheduler = 'tracealt'

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

	# Return the scheduling description as an array
	def self.get_scheduling(job)
		job = $db.select_one "SELECT scheduler_description FROM jobs WHERE id='#{job['id']}'"
		return job['scheduler_description'].split("\n")
	end

	# prepares the global timeline for "trace_alt" mode
	def self.prepare_timeline_alt(scheduling)
	
		# this first part creates a list of starts and stops (taken from jobd_trace.rb)
		time_line = {}
		thread_num = 1
		scheduling.each do |line|
			t = line.split(' ')
			run = true
			t.each do |a|
				a = a.to_i
				if not time_line[a]
					time_line[a] = {}
					time_line[a]['start'] = []
					time_line[a]['stop'] = []
				end
				if run
					time_line[a]['start'] << thread_num
					run = false
				else
					time_line[a]['stop'] << thread_num
					run = true
				end
			end
			thread_num += 1
		end

		# the second part replaces the start/stop approach with a list of nodes that are alive at all times.
		new_time_line = {}
		current_nodes = []
		time_line.sort_by { |k, v| k }.each do |old_time_line|
			t = old_time_line[0]
			tl = old_time_line[1]
			tl['start'].each do |n|
				current_nodes << n
			end
			tl['stop'].each do |n|
				current_nodes.delete(n)
			end
			new_time_line[t] = Array.new(current_nodes.sort)
		end

		return new_time_line
	end

	# prepares the node's timeline for "trace_alt" mode
	def self.prepare_my_timeline_alt(my_scheduling_str)
		my_time_line = []
		t = my_scheduling_str.split(' ')
		run = true
		t.each do |a|
			my_time_line << a.to_i
		end
		return my_time_line
	end

	# makes the raw list with timelines
	def self.raw_list_timeline(job, m_s_s, pos, max = 0)
		# regular raw_list from jobd.rb, which gives ref, position, nodes
		list = raw_list(job, m_s_s, max = 0)
		# position is no longer _POSITION_ since every JSON string is different from the beginning. there
		# is no generic JSON string anymore, that is customized on my_json from jobd.rb
		list['position'] = pos
		# prepares the global timeline
		list['timeline'] = prepare_timeline_alt(get_scheduling(job))
		# prepares the node's timeline
		if get_scheduling(job)[pos-1]
			list['my_timeline'] = prepare_my_timeline_alt(get_scheduling(job)[pos-1])
		end
		return list
	end

	def self.head_list_timeline(job, m_s_s, pos)
		return my_json(raw_list_timeline(job, m_s_s, pos, job['list_size'])) # a string now...
	end


	# Send the list of everybody selected by the query, to everybody selected by
	# the query.
	# (query should return values with splayd_id)
	def self.send_all_list_timeline(job, query)
		m_s_s = $db.select_all query

		case job['list_type']
		when 'HEAD' # simple head list of job['list_size'] element

			q_act = ""
			pos = 1
			m_s_s.each do |m_s|
				list_json = head_list_timeline(job, m_s_s, pos)
				q_act = q_act + "('#{m_s['splayd_id']}','#{job['id']}','LIST','#{pos}','#{list_json}'),"
				pos = pos + 1
			end
			q_act = q_act[0, q_act.length - 1]

			$db.do "INSERT INTO actions (splayd_id, job_id, command, position, data)
					VALUES #{q_act}"
		when 'RANDOM' # random list of job['list_size'] element

			lists = random_lists(job, m_s_s)
			# Complex list are all differents so they will be sent as a BIG SQL
			# request. Check MySQL packet size for limit.
			# TODO split in multiple request
			q_act = ""
			lists.each do |splayd_id, json|
				q_act += "('#{splayd_id}','#{job['id']}','LIST', '#{json}'),"
			end
			if q_act.size > 0
				q_act = q_act[0, q_act.length - 1]
				$db.do "INSERT INTO actions (splayd_id, job_id, command, data)
						VALUES #{q_act}"
			end
		end
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

				send_all_list_timeline(job, "SELECT * FROM splayd_selections WHERE
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

