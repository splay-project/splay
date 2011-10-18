## Splay Controller ### v1.1.1 ###
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


# Trace format:
# One line for each node with numbers describing the switch between up and down.
# Initial nodes must have a 0 at the beginning of their trace. By default, all
# initial nodes receive the list of all other initial nodes. Then, each node
# that becomes up receive the list of all nodes up before it comes.
# 
# We will register the job on every nodes.
#
# Example:
# 0 100 200
# 0 200 300
# 10 100 200 300
# 200
# 100 300
#
# 0: initial nodes (1 and 2) will be started and receive each of them in the list.
# 10: node 3 is started
# 100: node 1 and 3 are killed, node 5 is started and receive node 2 in the list.
# 200: node 2 is killed, nodes 1, 3 and 4 are started, they receive 5 in their list.
# 300: node 3 and 5 killed, node 2 start and receive 1 and 4 in their list.
#
# We will select the needed number of host * factor, so we will have a security
# if some goes down, we will not select new ones dinamically now.
#
# The precision depends of the splayd daemons latencies + job daemon latency +
# network latency => With the current settings don't expect better than +- 2
# seconds precision.
#
# NOTE
#
# Another problem: if a node, selected for the trace job, has a problem and
# comes back, it can be selected in splayd selection but it has been reset, so
# it has no more the job informations. To fix that, we have added a 'reset'
# entry in splayd_selections. When a node comes back with reset, all the entries
# in splayd_selections.reset are set to true.
#
# We send START even if status is UNAVAILABLE, because, if the splayd comes back
# not reset, it may then receive a STOP (without the previous START), that will
# raise an error (UNKNOWN_REF). A solution to that, will, in case where we add
# an action STOP and the action START is already queued, to remove both (but
# that can't be done so easily in general case because we need to deal with LIST
# and REGISTER too). But the solution to send all the command is not bad, in
# some case, splayd will come back a little later and will play its trace quite
# completly.

class JobdTrace < Jobd

	@@scheduler = 'trace'

	# We are just restarted, no threads to apply the trace, we need to kill
	# each running jobs
	def self.init()
		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='RUNNING'" do |job|
			kill_job(job, "controller restart, trace job aborted")
		end
	end

	def self.start_trace(job, trace_number, list)
		$log.info("TRACE #{job['id']}: start #{trace_number}")
					
		s_s = $db.select_one "SELECT * FROM splayd_selections
				WHERE
				job_id='#{job['id']}' AND
				trace_number='#{trace_number}'"
		s = Splayd.new(s_s['splayd_id'])

		$db.do "UPDATE splayd_selections SET
				trace_status='RUNNING'
				WHERE
				job_id='#{job['id']}' AND
				splayd_id='#{s.id}'"

		# If the splayd cannot be repaired the trace will stay on it but we
		# will do nothing.
		if s_s['reset'] == 'FALSE'
			if s.row['status'] != 'AVAILABLE'
				$log.info("TRACE #{job['id']}: start SENT (even if #{s.id} is not available)")
			end
			Splayd::add_action(s.id, job['id'], 'LIST', list)
			Splayd::add_action(s.id, job['id'], 'START', job['ref'])
		else
			$log.info("TRACE #{job['id']}: start NOT SENT (#{s.id} reset)")
		end
	end

	def self.stop_trace(job, trace_number)
		$log.info("TRACE #{job['id']}: stop #{trace_number}")

		s_s = $db.select_one "SELECT * FROM splayd_selections
				WHERE
				job_id='#{job['id']}' AND
				trace_number='#{trace_number}'"
		if s_s['trace_status'] == 'RUNNING'
			s = Splayd.new(s_s['splayd_id'])
			$db.do "UPDATE splayd_selections SET
					trace_status='WAITING'
					WHERE
					job_id='#{job['id']}' AND
					splayd_id='#{s.id}'"

			# Stop is called before repair (even after we need this check, see
			# start_trace()), so the node has maybe reset during the run.
			if s_s['reset'] == 'FALSE'
				if s.row['status'] != 'AVAILABLE'
					$log.info("TRACE #{job['id']}: stop SENT (even if #{s.id} is not available)")
				end
				Splayd::add_action(s.id, job['id'], 'STOP', job['ref'])
			else
				$log.info("TRACE #{job['id']}: stop NOT SENT (#{s.id} reset)")
			end
		end
	end

	# Replace failed nodes in the trace.
	def self.replace_failed(job)

		# Replace all nodes non AVAILABLE or RESET
		$db.select_all "SELECT * FROM splayds, splayd_selections
				WHERE
				splayd_selections.job_id='#{job['id']}' AND
				splayd_selections.trace_number IS NOT NULL AND
				splayds.id=splayd_selections.splayd_id AND
				(splayds.status!='AVAILABLE' OR
				splayd_selections.reset='TRUE')" do |old|
			repair(job, old)
		end
	end

	def self.repair(job, old)
		$log.warn("TRACE #{job['id']}: splayd #{old['splayd_id']} has failed.")

		new = $db.select_one "SELECT * FROM splayds, splayd_selections
				WHERE
				splayd_selections.job_id='#{job['id']}' AND
				splayd_selections.trace_number IS NULL AND
				splayd_selections.replied='TRUE' AND
				splayd_selections.reset='FALSE' AND
				splayds.id = splayd_selections.splayd_id AND
				splayds.status='AVAILABLE'
				ORDER BY reply_time"

		if not new
			$log.error("TRACE #{job['id']}: repair FAILED, no free splayds.")
			return false
		end

		trace_number = old['trace_number']
		stop_trace(job, trace_number)

		$db.do "UPDATE splayd_selections SET
				trace_number=NULL
				WHERE
				job_id='#{job['id']}' AND
				splayd_id='#{old['splayd_id']}'"

		$db.do "UPDATE splayd_selections SET
				trace_number='#{trace_number}'
				WHERE
				job_id='#{job['id']}' AND
				splayd_id='#{new['splayd_id']}'"

		if old['trace_status'] == 'RUNNING'
			$db.do "UPDATE splayd_selections SET
					trace_status='RUNNING'
					WHERE
					job_id='#{job['id']}' AND
					splayd_id='#{new['splayd_id']}'"

			# create the new list of running nodes
			list = running_list(job)

			Splayd::add_action(new['splayd_id'], job['id'], 'LIST', list)
			Splayd::add_action(new['splayd_id'], job['id'], 'START', job['ref'])
		end
		$log.info("TRACE #{job['id']}: repair OK: " +
				"#{new['splayd_id']} replace #{old['splayd_id']}")
	end

	# Return the scheduling description as an array
	def self.get_scheduling(job)
		job = $db.select_one "SELECT scheduler_description FROM
				jobs WHERE id='#{job['id']}'"
		return job['scheduler_description'].split("\n")
	end

	# create the new list of running nodes (this list must be done after
	# all reparations)
	def self.running_list(job)
		# Splayds already in the job
		splayds = $db.select_all "SELECT * FROM splayd_selections WHERE
				job_id='#{job['id']}' AND trace_status='RUNNING'"
		
		# head list
		r_list = raw_list(job, splayds, job['list_size'])
		r_list['position'] = r_list['nodes'].size() # to be out of the list...
		return my_json(r_list)
	end

	def self.start_nodes_list(scheduling)
		list = []
		number = 0
		scheduling.each do |line|
			number += 1
			t = line.split(' ')
			if t[0] == '0'
				list << number
			end
		end
		return list
	end

	def self.prepare_timeline(scheduling)
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
		return time_line
	end

	def self.thread(job)
		@@threads[job['id']] = Thread.new(job) do |job|
			begin
				time_line = prepare_timeline(get_scheduling(job))

				# Display all the timeline events
				#time_line.keys.sort.each do |time|
						#$log.info("TIME #{time}")
						#stops = time_line[time]['stop']
						#stops.each do |trace_number|
							#$log.info("STOP #{trace_number}")
						#end
						#starts = time_line[time]['start']
						#starts.each do |trace_number|
							#$log.info("START #{trace_number}")
						#end
				#end

				# Actually relative time
				# Problem with true time: if operations are too slow, we will need to
				# skip some steps to catch the loose time.
				t_time = 0
				time_line.keys.sort.each do |time|
					
					if time != 0

						# TODO less active (30s)
						(0...(time - t_time)).each do
							sleep(1)
							replace_failed(job)
						end
						t_time = time

						# sleep until the next events...
						#sleep(time - t_time)
						#t_time = time

						$log.info("TRACE #{job['id']}: time #{time}")

						stops = time_line[time]['stop']
						stops.each do |trace_number|
							stop_trace(job, trace_number)
						end

						#replace_failed(job)

						# create the new list of running nodes (this list must be done after
						# all reparations)
						list = running_list(job)

						starts = time_line[time]['start']
						starts.each do |trace_number|
							start_trace(job, trace_number, list)
						end
					end
				end
						
				$log.info("END OF TRACE")

        			# signal that trace ended
				q_act = ""
				$db.select_all "SELECT splayd_id FROM splayd_selections
						WHERE
						job_id='#{job['id']}'" do |splayd_id|

					q_act = q_act + "('#{splayd_id}','#{job['id']}','TRACE_END','#{job['ref']}','WAITING'),"
				end
				q_act = q_act[0, q_act.length - 1]

				$db.do "INSERT INTO actions (splayd_id, job_id, command, data, status) VALUES #{q_act}"

				while true do
					sleep(30)
					replace_failed(job)
				end

			rescue => e
				$log.fatal(e.class.to_s + ": " + e.to_s + "\n" + e.backtrace.join("\n"))
			end
		end
	end

	# LOCAL => REGISTERING|NO RESSOURCES
	def self.status_local
		@@dlock_jr.get

		c_splayd = nil

		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND
				status='LOCAL' AND die_free='FALSE'" do |job|

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
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}', 'TRUE'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"
	
				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1

				count += 1
				if count >= nb_selected_splayds then break end
			end

			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|

				splay_id = mm['splayd_id'] # bug?
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}', 'TRUE'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"

				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
			end
			q_sel = q_sel[0, q_sel.length - 1]
			q_job = q_job[0, q_job.length - 1]
			q_act = q_act[0, q_act.length - 1]
			# In trace jobs, all are selected and kept, but only those that have
			# replied will be used.
			$db.do "INSERT INTO splayd_selections (splayd_id, job_id, selected) VALUES #{q_sel}"
			$db.do "INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}"

			$db.do "INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}"
			$db.do "UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
					WHERE job_id='#{job['id']}' AND command='REGISTER' AND status='TEMP'"


			set_job_status(job['id'], 'REGISTERING')
		end
		@@dlock_jr.release
	end

	# REGISTERING => REGISTERING_TIMEOUT|RUNNING
	# NOTE don't apply mandatory in this step
	def self.status_registering
		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='REGISTERING'" do |job|

			# We will not use
			# selected='TRUE' 
			# in splayd_selections, all splayds will be kept. The possible ones will
			# be those with replied='TRUE'. The used ones will be those with a
			# trace_number not null. The active one, will be those with a trace_status
			# running.

			scheduling = get_scheduling(job)

			possible_splayds = []
			$db.select_all "SELECT splayd_id FROM splayd_selections WHERE
					job_id='#{job['id']}' AND
					replied='TRUE'
					ORDER BY reply_time LIMIT #{scheduling.size}" do |m|
				possible_splayds << m['splayd_id']
			end

			# check if enough splayds have responded at least one for each trace
			if possible_splayds.size == scheduling.size

				trace_number = 0
				possible_splayds.each do |splayd_id|
					$db.do("UPDATE splayd_selections SET
							trace_number='#{trace_number += 1}'
							WHERE
							splayd_id='#{splayd_id}' AND
							job_id='#{job['id']}'")
				end

				start_nodes = start_nodes_list(scheduling)

				start_nodes.each do |trace_number|
					$log.debug("TRACE #{job['id']}: initial #{trace_number}")
					$db.do("UPDATE splayd_selections SET
							trace_status='RUNNING'
							WHERE
							trace_number='#{trace_number}' AND
							job_id='#{job['id']}'")
				end

				if start_nodes.size > 0
					send_all_list(job, "SELECT * FROM splayd_selections WHERE
							job_id='#{job['id']}' AND trace_status='RUNNING'")
				end

				# We change it before sending the START commands because it
				# seems more consistant... We had problem with first jobs
				# begining to log before the status change was done and refused
				# by the log server.
				set_job_status(job['id'], 'RUNNING')

				# Create a symlink to the log dir
				File.symlink("#{@@log_dir}/#{job['id']}", "#{@@link_log_dir}/#{job['ref']}.txt")

				if start_nodes.size > 0
					send_start(job, "SELECT * FROM splayd_selections WHERE
							job_id='#{job['id']}' AND trace_status='RUNNING'")
				end
				
				thread(job)
			else
				Jobd.status_registering_common(job)
			end
		end
	end
	
	# RUNNING => ENDED
	def self.status_running
		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='RUNNING'" do |job|
			# TODO error msg...
			
			if not $db.select_one "SELECT * FROM splayd_jobs
				WHERE job_id='#{job['id']}' AND status!='RESERVED'"
				set_job_status(job['id'], 'ENDED')
			end
		end
	end

	def self.status_queued
		@@dlock_jr.get

		c_splayd = nil

		$db.select_all "SELECT * FROM jobs WHERE
				scheduler='#{@@scheduler}' AND status='QUEUED' 
				AND (scheduled_at is NULL OR scheduled_at<NOW()) AND die_free='FALSE'" do |job|

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
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}', 'TRUE'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"
	
				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1

				count += 1
				if count >= nb_selected_splayds then break end
			end

			$db.select_all "SELECT * FROM job_mandatory_splayds
					WHERE job_id='#{job['id']}'" do |mm|

				splay_id = mm['splayd_id'] # bug?
				q_sel = q_sel + "('#{splayd_id}','#{job['id']}', 'TRUE'),"
				q_job = q_job + "('#{splayd_id}','#{job['id']}','RESERVED'),"
				q_act = q_act + "('#{splayd_id}','#{job['id']}','REGISTER', 'TEMP'),"

				# We update the cache
				c_splayd['nb_nodes'][splayd_id] = c_splayd['nb_nodes'][splayd_id] + 1
			end
			q_sel = q_sel[0, q_sel.length - 1]
			q_job = q_job[0, q_job.length - 1]
			q_act = q_act[0, q_act.length - 1]
			# In trace jobs, all are selected and kept, but only those that have
			# replied will be used.
			$db.do "INSERT INTO splayd_selections (splayd_id, job_id, selected) VALUES #{q_sel}"
			$db.do "INSERT INTO splayd_jobs (splayd_id, job_id, status) VALUES #{q_job}"

			$db.do "INSERT INTO actions (splayd_id, job_id, command, status) VALUES #{q_act}"
			$db.do "UPDATE actions SET data='#{addslashes(new_job)}', status='WAITING'
					WHERE job_id='#{job['id']}' AND command='REGISTER' AND status='TEMP'"


			set_job_status(job['id'], 'REGISTERING')
		end
		@@dlock_jr.release
	end

	def self.kill_job(job, status_msg)
		$log.info("KILLING #{job['id']}")
		if @@threads[job['id']] then
			@@threads[job['id']].kill
		else
			$log.warn("TRACE THREAD NOT FOUND (#{job['id']})")
		end
		Jobd.status_killed_common(job, status_msg)
	end

	def self.command
		# NOTE splayd_jobs table is cleaned directly by splayd when it apply the
		# unregister command (or reset)
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
