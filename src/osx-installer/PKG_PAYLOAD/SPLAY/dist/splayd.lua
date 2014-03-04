--[[
       Splay ### v1.3 ###
       Copyright 2006-2011
       http://www.splay-project.org
]]

--[[
This file is part of Splay.

Splay is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published
by the Free Software Foundation, either version 3 of the License,
or (at your option) any later version.

Splay is distributed in the hope that it will be useful,but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Splayd. If not, see <http://www.gnu.org/licenses/>.
]]

--[[
NOTE:
For common settings, edit settings.lua, for advanced configuration, see
SETTINGS section near the end of this file.
]]

_COPYRIGHT = "Copyright 2006 - 2011"
_SPLAYD_VERSION = 1.2

require"table"
require"math"
require"os"
require"string"
require"io"

require"json"
require"splay"
crypto = require"crypto"
evp = crypto.evp

llenc = require"splay.llenc"

require"base64"
math.randomseed(os.time())

do
	local p = print
	print = function(...)
		p(...)
		io.flush()
	end
end

--[[ Logs ]]--

function prepare_dir(dir)
	if not splay.dir_exists(dir) and not splay.mkdir(dir) then
		print("Impossible to create "..dir)
		os.exit()
	end
	if not splay.dir_writable(dir) then
		print("Impossible to write into "..dir)
		os.exit()
	end
end

--[[ Local FS functions ]]--

function clean_dir(dir, rec)
	if not rec then
		rec = false
	end
	if rec then
		os.execute("rm -fr "..dir.."/* > /dev/null 2>&1")
	else
		os.execute("rm -f "..dir.."/* > /dev/null 2>&1")
	end
end

function init_job_dir(dir)
	if string.sub(dir, #dir, #dir) == "/" then
		print("Job directory must not end with a /")
		return false
	end

	prepare_dir(dir)

	os.execute("rm -fr "..dir.."/* > /dev/null 2>&1")
	return true
end

function init_job_lib_dir(dir)
	if string.sub(dir, #dir, #dir) == "/" then
		print("Job directory must not end with a /")
		return false
	end
	prepare_dir(dir)
end
--[[ Common functions ]]--

-- called after a fork
function start_job(job, ref, script)

	if not script then
		job._SPLAYD_VERSION = _SPLAYD_VERSION
		job.network.local_start_port = splayd.settings.job.network.start_port
		job.network.local_end_port = splayd.settings.job.network.end_port
		if production then
			job.remove_file = true
		end
	end

	local job_file = jobs_dir.."/"..ref.."_"..splayd.settings.key
	if script then job_file = job_file.."_script" end
	
	if job.network.list.topology~=nil then
                local topo_json=json.encode(job.network.list.topology)
                local topo_file = jobs_dir.."/"..ref.."_"..splayd.settings.key.."_topology"
                local f, err = io.open(topo_file, "w")
                if not f then
                        print("Can't create topology file, Error: ", err)
                        os.exit()
                end
                f:write(topo_json)
                f:close()
                --print("Topology file saved in:", topo_file)
                job.network.list.topology=nil --gc to remove duplicate from job_file content
                job.topology=topo_file
        end

	
	local content = json.encode(job)
	if script then content = job.script end

	local f, err = io.open(job_file, "w")
	if not f then
		print("Error: ", err)
		os.exit()
	end
	f:write(content)
	f:close()

	local log_file = "-" -- default = no log file
	if jobs_log then
		log_file = jobs_logs_dir.."/"..ref.."_"..splayd.settings.key
		if script then log_file = log_file.."_script" end
	end
	local typ = "lua"
	if script then typ = "exec" end

	-- run jobd
	local ok, err = splay.exec("./jobd", job_file, log_file,
			splayd.settings.log.ip, splayd.settings.log.port,
			ref, splayd.session, splayd.settings.log.max_size, typ,
			json.encode(job.network))

	-- If we are here, that means an exec() error..
	print("Error: ", err)
	os.exit()
end

function start(ref)

	local job = splayd.jobs[ref]

	-- we release the ports we have locked for this job
	if job.network.nb_ports > 0 then
		splay.release_ports(job.me.port,
				job.me.port + job.network.nb_ports - 1)
	end

	local pid, err, err_code = splay.fork()

	if pid ~= nil then

		if pid > 0 then -- splayd

			job.pid = pid
			job.status = "running"
			job.start_time = os.time()

		else -- jailer (forked)

			-- WARNING: if both script and code are executed, job will only
			-- watch lua (code) and kill will only kill lua (code).
			-- We will need a new fork...
			if job.code and job.script and exec_script then
				pid, err, err_code = splay.fork()
				if pid ~= nil then
					if pid > 0 then
						-- Important to run the job here because splayd is watching only
						-- this pid !
						start_job(job, ref)
					else
						start_job(job, ref, true)
					end
				else
					print("2nd fork error: "..err, err_code)
					os.exit()
				end
			else -- or not
				if job.code then
					start_job(job, ref)
				end
				if job.script and exec_script then
					start_job(job, ref, true)
				end
			end
			-- In any case, this process will die (security)
			os.exit()
		end
	else
		print("Fork error: "..err, err_code)
		os.exit()
	end
end

-- Free a job slot
function free(ref)
	stop(ref, true)

	-- we release the ports we have locked for this job
	-- it's a security, if the job has never run
	if splayd.jobs[ref].network.nb_ports > 0 then
		splay.release_ports(splayd.jobs[ref].me.port,
				splayd.jobs[ref].me.port + splayd.jobs[ref].network.nb_ports - 1)
	end

	-- if the job had a "trace_alt" churn trace
	if splayd.churn_mgmt_jobs[ref] then
		-- remove the job from the list of churn jobs
		splayd.churn_mgmt_jobs[ref] = nil
	end

	splayd.jobs[ref] = nil
end

-- Stop a job
function stop(ref, free)
	-- If called on a really running job, compute the execution time
	if splayd.jobs[ref].status == "running" then
		splay.kill(splayd.jobs[ref].pid)
		splayd.jobs[ref].pid = 0
		splayd.jobs[ref].execution_time = os.time() - splayd.jobs[ref].start_time
	end
	splayd.jobs[ref].status = "waiting"
	clean_dir(splayd.jobs[ref].disk.directory)

	if not free then
		-- try to reserve ports again (best effort)
		if splayd.jobs[ref].network.nb_ports > 0 then
			splay.reserve_ports(splayd.jobs[ref].me.port,
					splayd.jobs[ref].me.port + splayd.jobs[ref].network.nb_ports - 1)
		end
	end
end

-- Reset the splayd to the initial state (excluding the session)
function reset()
	for ref, job in pairs(splayd.jobs) do
		free(ref)
	end
	-- normally not needed
	splayd.jobs = {}
	clean_dir(splayd.settings.job.disk.directory, true)
end

function free_ended_jobs()
	for ref, job in pairs(splayd.jobs) do
		if job.status == "running" then
			if not splay.alive(job.pid) then
				if job.die_free then
					free(ref)
				else
					if job_trace_ended[ref] == true then
						free(ref)
					else
						stop(ref)
					end
				end
			end
		end
	end
end

--[[
The splayd will try to randomly find (and reserve) a range of
<nb_ports> ports in the full port range and return it. The full range
will be scanned until we find one.

We suppose the avaible port range beeing a lot of wider than the range to
reserve.

The random separator (r_start), deny the algorythm to test all the
possibilities, but given the above condition that should not be a problem.
--]]
function find_reserve_rand_ports(nb_ports)
	local s = splayd.settings.job
	local r_start = math.random(s.network.start_port, s.network.end_port)
	return find_reserve_ports(nb_ports, r_start, s.network.end_port) or
			find_reserve_ports(nb_ports, s.network.start_port, r_start - 1)
end

function find_reserve_ports(nb_ports, start_port, end_port)
	while start_port + nb_ports - 1 <= end_port do

		local ok = true
		-- We verify that other jobs don't overlap the port range.
		for _, sl in pairs(splayd.jobs) do
			if sl.network.nb_ports > 0 then
				local s_start_port = sl.me.port
				local s_end_port = s_start_port + sl.network.nb_ports - 1

				if s_start_port <= start_port then
					if s_end_port >= start_port then
						ok = false
						start_port = s_end_port -- + 1 done at the end of the loop
						break
					end
				else
					if s_start_port <= start_port + nb_ports - 1 then
						ok = false
						start_port = s_end_port -- + 1 done at the end of the loop
						break
					end
				end
			end
		end

		if ok then
			-- We verify that another application doesn't use one of the ports.
			local status, msg, port = splay.reserve_ports(start_port, start_port + nb_ports - 1)
			if status then
				return start_port
			else
				start_port = port
			end
		end
		start_port = start_port + 1
	end
	return nil
end

--[[ Network protocol ]]--

function n_reset(so)
	-- every function that handles commands sets timeout to nil (blocking socket) until the answer is sent
	so:settimeout(nil)
	reset()
	assert(so:send("OK"))
	-- then the timeout is restablished to what it was before: 0 (non-blocking socket) when there are churn jobs, nil if not
	so:settimeout(so_timeout)
end

function blacklist(so)
	-- blocking socket
	so:settimeout(nil)
	local blacklist = json.decode(assert(so:receive()))


	for _, b in pairs(blacklist) do
		splayd.blacklist[#splayd.blacklist + 1] = b
	end

	assert(so:send("OK"))
	-- restablish timeout
	so:settimeout(so_timeout)
end

function register(so)
	-- blocking socket
	so:settimeout(nil)
	local s = splayd.settings.job

	local job = json.decode(assert(so:receive()))
	local ref = job.ref

	if splayd.jobs[ref] then
		assert(so:send("EXISTING_REF"))
		return
	end

	-- Check for max_number
	local nb_jobs = 0
	for _, _  in pairs(splayd.jobs) do
		nb_jobs = nb_jobs + 1
	end
	if nb_jobs >= s.max_number then
		assert(so:send("NO_NEW"))
		return
	end

	--[[ We will correct, validate and complete job settings.
	Missing limits will get the splayd's limits.

	We complete them here like that, successive "modules" that have no access
	to splayd limitations can use them directly.
	]]--

	if not job.name then
		job.name = ""
	end

	if not job.description then
		job.description = ""
	end

	-- No more INVALID_CODE error
	-- We will always execute some code (even empty), to create some logs
	if job.code and job.code == "" then job.code = nil end
	if job.script and job.script == "" then job.script = nil end
	if not job.code and not job.script then
		job.code = ""
	end

	if not job.max_mem then
		job.max_mem = s.max_mem
	else
		if s.max_mem < job.max_mem then
			assert(so:send("INVALID_MEM"))
			return
		end
	end

	if not job.disk then
		job.disk = {}
	end

	job.disk.clean = true

	if not job.disk.max_size then
		job.disk.max_size = s.disk.max_size
	else
		if s.disk.max_size < job.disk.max_size then
			assert(so:send("INVALID_DISK"))
			return
		end
	end

	if not job.disk.max_files then
		job.disk.max_files = s.disk.max_files
	else
		if s.disk.max_files < job.disk.max_files then
			assert(so:send("INVALID_FILES"))
			return
		end
	end

	if not job.disk.max_file_descriptors then
		job.disk.max_file_descriptors = s.disk.max_file_descriptors
	else
		if s.disk.max_file_descriptors < job.disk.max_file_descriptors then
			assert(so:send("INVALID_FILE_DESCRIPTORS"))
			return
		end
	end

	if not job.network then
		job.network = {}
	end

	if not job.network.max_send then
		job.network.max_send = s.network.max_send
	else
		if s.network.max_send < job.network.max_send then
			assert(so:send("INVALID_SEND"))
			return
		end
	end

	if not job.network.max_receive then
		job.network.max_receive = s.network.max_receive
	else
		if s.network.max_receive < job.network.max_receive then
			assert(so:send("INVALID_RECEIVE"))
			return
		end
	end

	if not job.network.max_sockets then
		job.network.max_sockets = s.network.max_sockets
	else
		if s.network.max_sockets < job.network.max_sockets then
			assert(so:send("INVALID_SOCKETS"))
			return
		end
	end

	-- We fill missing ip if needed
	if not job.network.ip then
		job.network.ip = "127.0.0.1"
	end

	job.me = {
		ip = splayd.ip,
		port = 0
	}

	-- We find nb_ports free ports
	if not job.network.nb_ports then
		job.network.nb_ports = 0
	else
		if job.network.nb_ports > 0 then
			if job.network.nb_ports > s.network.max_ports then
				assert(so:send("INVALID_PORTS"))
				return
			end
			local port = find_reserve_rand_ports(job.network.nb_ports)
			if port then
				job.me.port = port
			else
				assert(so:send("BUSY_PORTS"))
				return
			end
		end
	end

	job.execution_time = 0

	if not job.die_free then
		job.die_free = true -- default
	elseif job.die_free == "FALSE" then
		job.die_free = false
	end

	if not job.keep_files then
		job.keep_files = false -- default
	elseif job.keep_files == "TRUE" then
		job.keep_files = true
	end

	-- corrections finished, we will now add some extra informations to the
	-- job description

	job.disk.directory = s.disk.directory.."/"..ref
	splay.mkdir(job.disk.directory)

	if not prepare_lib_directory(job) then
		assert(so:send("DEPENDENCIES NOT OK"))
		return
	end
	job.status = "waiting"

	-- We give the blacklist to the job.
	job.blacklist = splayd.blacklist

	-- Settings fnished
	splayd.jobs[ref] = job

	assert(so:send("OK"))
	assert(so:send(job.me.port))
	-- restablish timeout
	so:settimeout(so_timeout)
end

function prepare_lib_directory(job)
	if job.disk then
		job.disk.lib_directory = job.disk.directory.."/".."lib"
		splay.mkdir(job.disk.lib_directory)
		if job.lib_code and job.lib_code ~= "" then
			local lib_file = io.open(libs_cache_dir.."/".. job.lib_sha1, "w+")
			local lib_code = base64.decode(job.lib_code)
			local sha1=evp.new("sha1")
			local lib_code_sha1 =  sha1:digest(lib_code)

			if (lib_code_sha1 == job.lib_sha1) then
				lib_file:write(lib_code)
				lib_file:close()
				job.lib_code = nil
				collectgarbage()
			else
				print("Wrong checksum for lib "..job.lib_name.."\ncomputed : "..lib_code_sha1.."\nRegistered as : "..job.lib_sha1)
				return false
			end
		end
		if job.lib_name and job.lib_name ~= "" then
			os.execute("ln "..libs_cache_dir.."/"..job.lib_sha1.. " " .. job.disk.lib_directory.."/"..job.lib_name)
		end
	else
		print("Wrong job configuration")
		return false
	end
	return true
end

function n_free(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())
	if splayd.jobs[ref] then
		free(ref)
		assert(so:send("OK"))
	else
		assert(so:send("UNKNOWN_REF"))
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end

function n_log(so)
	-- blocking socket
	so:settimeout(nil)
	splayd.settings.log = json.decode(assert(so:receive()))
	if not splayd.settings.log.ip then
		splayd.settings.log.ip = splayd.settings.controller.ip
	end
	assert(so:send("OK"))
	-- restablish timeout
	so:settimeout(so_timeout)
end

function list(so)
	-- blocking socket
	so:settimeout(nil)
	local list = json.decode(assert(so:receive()))
	local ref = list.ref

	if not splayd.jobs[ref] then
		assert(so:send("UNKNOWN_REF"))
		return
	end
	job = splayd.jobs[ref]

	-- We append the list to the job configuration.
	list.ref = nil
	job.network.list = list
	assert(so:send("OK"))
	-- restablish timeout
	so:settimeout(so_timeout)
end

function loadavg(so)
	-- blocking socket
	so:settimeout(nil)
	assert(so:send("OK"))
	if splayd.status.os == "Linux" then
		local p_avg=assert(io.open("/proc/loadavg","r"))
		if p_avg then
			local f = string.gmatch(p_avg:read(), "%d+.%d+")
			assert(so:send(f().." "..f().." "..f()))
		else
			assert(so:send("-1 -1 -1")) --status error?
		end
		p_avg:close()
 	elseif splayd.status.os == "Darwin" then
		local fh=assert(io.popen("sysctl -n vm.loadavg","r"))
		local lf=fh:read():match("%d+.%d+ %d+.%d+ %d+.%d+")
		assert(so:send(lf))
		fh:close()
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end


-- coroutine that handles start/stop events for "trace_alt" churning jobs
function churn_mgmt()
	-- initializes count msleep as 10
	local count_msleep = 10
	-- eternal loop (has a break inside)
	while true do
		-- if count msleep = 10 (every second; 1 sleep = 100ms)
		if count_msleep == 10 then
			-- initializes number of churn jobs
			local n_churn_jobs = 0
			-- for all jobs in the table of active churning jobs
			for i,v in pairs(splayd.churn_mgmt_jobs) do
				-- increments the number of churn jobs
				n_churn_jobs = n_churn_jobs + 1
				-- increments the count of seconds that has passed for that job
				splayd.churn_mgmt_jobs[i] = v + 1
				-- turn on is true by default
				local turn_on = true
				-- takes the timeline of the job
				local my_timeline = splayd.jobs[i].network.list.my_timeline
				-- for all "times" in the timeline
				for i2,v2 in ipairs(my_timeline) do
					-- if one of the times is exactly equal to the delayed time of that job
					if v == v2 then
						-- if that "time" element has an even position on the timeline... it is a stop
						if i2 % 2 == 0 then
							-- if it is the last one
							if i2 == #my_timeline then
								-- it is a "free" (end of the trace)
								free(i)
							else
								-- if not, it is a simple "stop" (later there will be another start)
								stop(i)
							end
						else
							-- if the position is odd, it is a "start"
							start(i)
						end
						-- stop looking the timeline table
						break
					end
					-- reverse turn-on (in fact, i think i don't use this anymore, TODO check if it is used)
					turn_on = not turn_on
				end
			end
			-- if number of jobs is 0 (there were no jobs on the table)
			if n_churn_jobs == 0 then
				-- break the eternal loop (it will cause death of the coroutine, until a churn job
				-- arrives and creates a new one)
				break
			end
			-- reset count msleep to 0
			count_msleep = 0
		end
		-- sleep for 100ms
		splay.msleep(100)
		-- increment count msleep
		count_msleep = count_msleep + 1
		-- yield
		coroutine.yield()
	end
end

function n_start(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())
	if splayd.jobs[ref] then
		if splayd.jobs[ref].status == "running" then
			assert(so:send("RUNNING"))
			return
		end
		-- if the job has a timeline (trace_alt type)
		if splayd.jobs[ref].network.list.my_timeline then
			-- initializes the running time of that job to 0
			splayd.churn_mgmt_jobs[ref] = 0
			-- saves a timestamp of the start time
			splayd.jobs[ref].network.list['start_time'] = os.time()
			-- if this is the first job to be added to the table
			if size_of_table(splayd.churn_mgmt_jobs) == 1 then
				-- set socket timeout to 0 (non-blocking socket)
				so:settimeout(0)
				-- so_timeout also to 0, to keep track of that
				so_timeout = 0
				-- creates the churn coroutine
				co_churn = coroutine.create(churn_mgmt)
			end
		else
			--if the job doesn't have timeline, simply start (normal job)
			start(ref)
		end
		assert(so:send("OK"))
	else
		assert(so:send("UNKNOWN_REF"))
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end

function n_stop(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())
	if splayd.jobs[ref] then
		if splayd.jobs[ref].status ~= "running" then
			assert(so:send("NOT_RUNNING"))
			return
		end
		stop(ref)
		assert(so:send("OK"))
	else
		assert(so:send("UNKNOWN_REF"))
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end

function restart(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())
	if err then return false end
	if splayd.jobs[ref] then
		if splayd.jobs[ref].status ~= "running" then
			assert(so:send("NOT_RUNNING"))
			return
		end
		stop(ref)
		start(ref)
		assert(so:send("OK"))
	else
		assert(so:send("UNKNOWN_REF"))
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end

-- The controller ask for theses infos only once (by session).
function infos(so)
	-- blocking socket
	so:settimeout(nil)
	-- We update our IP as seen by the controller
	splayd.ip = assert(so:receive())
	local m_tmp = {}
	m_tmp.settings = splayd.settings
	m_tmp.status = splayd.status

	assert(so:send("OK"))
	assert(so:send(json.encode(m_tmp)))
	-- restablish timeout
	so:settimeout(so_timeout)
end

-- This function should be called regulary from the controller, it acts as a
-- "cron" in our splayd.
-- It sends (light) job informations of the splayd.
function status(so)
	-- blocking socket
	so:settimeout(nil)
	local m_tmp = {}

	free_ended_jobs()

	-- We select a minimal set of job informations to send.
	m_tmp.jobs = {}
	for ref, job in pairs(splayd.jobs) do

		m_tmp.jobs[ref] = {}
		m_tmp.jobs[ref].status = job.status
		--[[
		if job.status == "running" then
			m_tmp.jobs[ref].execution_time = os.time() - job.start_time
		else
			m_tmp.jobs[ref].execution_time = job.execution_time
		end
		--]]
	end

	assert(so:send("OK"))
	assert(so:send(json.encode(m_tmp)))
	-- restablish timeout
	so:settimeout(so_timeout)
end

function local_log(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())
	if splayd.jobs[ref] then
		local log_file = jobs_logs_dir.."/"..ref.."_"..splayd.settings.key
		local f = io.open(log_file)
		if f then
			assert(so:send("OK"))
			assert(so:send(f:read()))
			return
		end
	end
	assert(so:send("NOT_FOUND"))
	-- restablish timeout
	so:settimeout(so_timeout)
end

-- Halt only if no jobs are still registered.
function halt(so)
	-- blocking socket
	so:settimeout(nil)
	free_ended_jobs()

	for ref, job in pairs(splayd.jobs) do
		assert(so:send("JOBS_REGISTERED"))
		return false
	end

	running = false
	assert(so:send("OK"))
	-- restablish timeout
	so:settimeout(so_timeout)
	return true
end

function test(so)
	local pid = splay.fork()
	local s

	if pid <= 0 then -- job
		print("FORK")
		s = nil

		-- assert(so:send("FORK"))
		if SSL then
			--so:clear()
			s = nil
			print("QUIT")
			os.exit()
		else
			--so:close()
			print("QUIT")
			os.exit()
		end
	end
end

function halt_splayd()
	running = false
end

function trace_end(so)
	-- blocking socket
	so:settimeout(nil)
	local ref = assert(so:receive())

	job_trace_ended[ref] = true
	assert(so:send("OK"))

	if splayd.jobs[ref].status == "waiting" then
		free(ref)
	end
	-- restablish timeout
	so:settimeout(so_timeout)
end

function server_loop(so)
		while true do
			splayd.last_connection_time = os.time()

			local msg = so:receive()

			-- if there is a msg (msg can be empty when using non-blocking sockets - when the churn coroutine is active)
			if msg then

				print("Command: "..msg)
				if msg == "PING" then
					-- blocking socket
					so:settimeout(nil)
					assert(so:send("OK"))
					-- restablish timeout
					so:settimeout(so_timeout)
				elseif msg == "BLACKLIST" then
					blacklist(so)
				elseif msg == "REGISTER" then
					register(so)
				elseif msg == "FREE" then
					n_free(so)
				elseif msg == "UNREGISTER" then -- deprecated
					n_free(so)
				elseif msg == "LOG" then
					n_log(so)
				elseif msg == "LOCAL_LOG" then
					local_log(so)
				elseif msg == "LIST" then
					list(so)
				elseif msg == "RESET" then
					n_reset(so)
				elseif msg == "START" then
					n_start(so)
				elseif msg == "RESTART" then
					restart(so)
				elseif msg == "STOP" then
					n_stop(so)
				elseif msg == "INFOS" then
					infos(so)
				elseif msg == "STATUS" then
					status(so)
				elseif msg == "TRACE_END" then
					trace_end(so)
				elseif msg == "LOADAVG" then
					loadavg(so)
				elseif msg == "HALT" then
					if (halt(so)) then
						break
					end
				elseif msg == "KILL" then
					running = false
					break
				elseif msg == "ERROR" then
					break

				--[[ Next one(s) are for testing only ]]--
				elseif msg == "TEST" then
					-- blocking socket
					so:settimeout(nil)
					assert(so:send("OK"))
					-- restablish timeout
					so:settimeout(so_timeout)
					test(so)
				else
					print("Unknow command.")
					break
				end
			end

			-- if there is a churn coroutine
			if co_churn then
				-- if the coroutine is not dead
				if coroutine.status(co_churn) ~= "dead" then
					-- yield (if the coroutine is dead, no need to yield)
					coroutine.yield()
				else
					-- if churn coroutine is dead set the socket timeout to nil (blocking socket)
					so:settimeout(nil)
					so_timeout = nil
				end
			end

    end
end

-- to calculate the size of a table (not array)
function size_of_table(t)
	local size = 0
	for i,v in pairs(t) do
		size = size + 1
	end
	return size
end

-- Return a table of all libs in the cache and their hash
function list_libs_in_cache(dir)
	
	local libs_list = io.popen("ls "..dir):read("*a")
	local lib_table = {}
	local name_table = {}
	local sha1_table = {}
	local lib = nil
	local lib_sha1 = nil
	-- TODO Find another pattern
	for lib_name in string.gmatch(libs_list, "[^%s]+") do
		lib = io.open(dir.."/"..lib_name):read("*a")
		local sha1=evp.new("sha1")
		lib_sha1 =  sha1:digest(lib)
		print("splayd.lua:list_libs file with sha1 ",lib_sha1)
		table.insert(lib_table, {name = lib_name, sha1 = lib_sha1})
	end
	
	return lib_table
end

-- Reads the libs in the cache, send them to the controller and 
-- according to the controller update the old ones and add the new ones
function check_libs(so)
	local libs_in_cache = list_libs_in_cache(libs_cache_dir)
	local msg = json.encode(libs_in_cache)
	assert(so:send(msg))
	local response = nil
	response = assert(so:receive())
	local old_libs = json.decode(response)
	
	clean_libs(libs_cache_dir, old_libs)
	assert(so:send("OK"))
	--return new_libs
end
-- Update the cache by updating old libs and adding new ones.
function clean_libs(dir, old_libs)
	for i,v in pairs(old_libs) do
			os.execute("rm "..dir.."/"..v['name'])
	end
	
end

function controller(so)
	print("Controller registration")
	-- Send the splayd-type
	assert(so:send(splayd.settings.protocol))
	-- the splayd registers on the Controller
	assert(so:send("KEY"))
	assert(so:send(splayd.settings.key))
	assert(so:send(splayd.session))
	
	-- The splayd lists the libs it already has in its cache.
	-- It informs the controller of the libs that it has.
	

	-- call only if settings splayd-type == 'grid'
	if splayd.settings.protocol == "grid" then
		check_libs(so)
	end
	
	local msg = assert(so:receive())
	if msg ~= "OK" then
		local reason = assert(so:receive())
		print("Refused: "..reason)
		if not always_run then
			running = false
		end
		return
	end

	local session = assert(so:receive())
	if splayd.session ~= session then
		reset()
		splayd.session = session
	end

	print("Waiting for commands.")

	-- creates a coroutine for the server loop
	co_server_loop = coroutine.create(function()
		server_loop(so)
	end)
	coroutine.resume(co_server_loop)

	-- as long as the server loop coroutine is not dead, alternate eternally between churn coroutine and server loop coroutine
	while coroutine.status(co_server_loop) ~= "dead" do
		coroutine.resume(co_server_loop)
		coroutine.resume(co_churn)
	end



end

function check()
	local s = splayd.settings.job

	-- Force right settings when using in production.
	if production and not splayd.set_max_mem then
		print("Production mode must be run from the C daemon.")
		return false
	end

	if lua_version ~= _VERSION then
		print("Lua versions don't match. You need "..lua_version..
				", you have ".._VERSION..".")
		return false
	end

	if
			not (s.max_number > 0) or
			not (s.max_mem > 0) or
			not (s.disk.max_size > 0) or
			not (s.disk.max_files > 0) or
			not (s.disk.max_file_descriptors > 0) or
			not (s.network.max_send > 0) or
			not (s.network.max_receive > 0) or
			not (s.network.max_sockets > 0) or
			not (s.network.max_ports > 0) or
			not (s.network.start_port > 0) or
			not (s.network.end_port > 0) then

		-- unlimited is NOT acceptable (and is a non sense)
		print("Limits MUST have values > 0. Check your settings.")
		return false
	end

	if not init_job_dir(s.disk.directory) then
		print("Job directory problem.")
		return false
	end

	if s.network.end_port - s.network.start_port <
			s.network.max_ports * (s.max_number + 1) then
		print("Your port range is too small respect to number of jobs and max_ports.")
		return false
	end
	return true
end

--[[ Display Config ]]--

function display_config()
	local m = splayd.settings
	local s = splayd.settings.job
	local ss = splayd.status
	-- Partially hide "true" keys
	local key
	if string.len(m.key) > 20 then
		key = string.sub(m.key, 1, 20).."..."
	else
		key = m.key
	end
	print()
	print(">>> Splayd v."..ss.version.." <<<")
	print()
	print("http://www.splay-project.org")
	print("Splayd is licensed under GPL v3, see COPYING")
	print()
	print(">> NAME: "..m.name)
	print(">> KEY: "..key)
	if m.endian == 1 then endian = "big" else endian = "little" end
	print(">> Running on "..ss.bits.."bits "..ss.os.." ("..endian.." endian)")
	if jobs_log then
		print(">> Log directory: "..jobs_logs_dir)
	end
	print()
	print(">> Job settings (max "..s.max_number.."):")
	print("    Max memory: "..(s.max_mem / 1024 / 1024).." Mo")
	print("    Max disk: "..(s.disk.max_size / 1024 / 1024).." Mo")
	print("    Max ports: "..s.network.max_ports.." port(s)")
	print("    Bandwith: send "..(m.network.send_speed / s.max_number / 1024).." ko/s"..
			" receive "..(m.network.receive_speed / s.max_number / 1024).." ko/s")
	print("    FS directory: "..s.disk.directory)
	print()
	print(">> Total:")
	print("    Max memory: "..(s.max_number * s.max_mem / 1024 / 1024).." Mo")
	print("    Max disk: "..(s.max_number * s.disk.max_size / 1024 / 1024).." Mo")
	print("    Max ports: "..(s.max_number * s.network.max_ports).." in range: "..
			s.network.start_port.."-"..s.network.end_port)
	print("    Bandwith: send "..(m.network.send_speed / 1024).." ko/s"..
			" receive "..(m.network.receive_speed / 1024).." ko/s")
	print()
	if not production then
		print(">> WARNING: You are not in production mode.")
	end
	if not SSL then
		print(">> WARNING: SSL disabled.")
	end
	if connect_retry_timeout < 120 then
		print(">> WARNING: connect_retry_timeout should be at least 120 seconds.")
	end
	if max_disconnection_time ~= 3600 then
		print(">> WARNING: max_disconnection_time must be 3600 seconds.")
	end
	if not always_run then
		print(">> WARNING: always_run must be set to true.")
	end
	if jobs_log then
		print(">> WARNING: jobs_log must be set to false.")
	end
	print()
end

--[[ Starting Splayd Network Code ]]--

function run()
	-- Can be set to false, for example if the Controller refuse us
	running = true

	print(">> Trying to connect to the Controller: "..
			splayd.settings.controller.ip..":"..splayd.settings.controller.port.."\n")

	while running do
		local status, err, so = nil, nil, assert(socket.tcp())
		collectgarbage()
		collectgarbage()
		status, err = so:connect(splayd.settings.controller.ip,
				splayd.settings.controller.port)
		so:setoption('keepalive', true)

		-- LuaSec
		if SSL and status then
			-- TLS/SSL client parameters
			local params = {
				mode = "client",
				protocol = "sslv3",
				verify = "none",
				options = "all",
				-- Optional if luasec 0.21+
				key = "key.pem",
				certificate = "client.pem",
			}
			so, err = ssl.wrap(so, params)
			if not so then
				print("Error creating SSL socket:", err)
				os.exit()
			end
			status, err = so:dohandshake()
		end

		if status then
			print("Connected")
			status, err = pcall(function() controller(llenc.wrap(so)) end)

			if err then
				print("Disconnected: "..err)
			else
				print("Disconnected")
			end
		else
			print("Connecting problem: "..err)
		end

		so:close()

		if running then
			local sec = math.random(0, connect_retry_timeout * 2)
			print("Trying to re-connect to the Controller in average "..
					connect_retry_timeout.." seconds ("..sec.." this time).")
			splay.sleep(sec)
		end
		-- It's not acceptable that the splayd continue a long time without
		-- having a contact with the controller.
		-- We reset everything if there is a very long disconnection.
		if splayd.last_connection_time ~= 0 and
				os.time() - splayd.last_connection_time > max_disconnection_time then
			print("Too much time since last connection, full reset.")
			splayd.last_connection_time = 0
			reset()
			splayd.session = "" -- to show a full reset to the controller
		end
	end
end

--[[ Code start ]]--

-- splayd exists if daemon is run from C
if not splayd then splayd = {} end

-- In production MUST BE true (enforce all the limitations, apply the strict
-- behavior), your security is only guaranted when this is set to true.
production = true

--[[ SETTINGS (if not in production mode) ]]--

root_dir = io.popen("pwd"):read()
libs_cache_dir = root_dir.."/libs_cache"
logs_dir = root_dir.."/logs"
jobs_logs_dir = root_dir.."/logs/jobs"
jobs_dir = root_dir.."/jobs"
jobs_fs_dir = root_dir.."/jobs_fs" -- then splayd.settings.job.disk.directory
jobs_lib_dir = jobs_fs_dir.."/lib"


lua_version = "Lua 5.1" -- Do not run without this version.
SSL = true -- Use SSL instead of plain text connection.
connect_retry_timeout = 180 -- Average reconnect time when connection loose.
max_disconnection_time = 3600 -- Reset jobs in case of a very long disconnection.
always_run = true -- Try to reconnect even if rejected by the controller.
-- Allow execution of an untrusted executable (only for specific deployments)
exec_script = false

-- Will log splayd's output in logs_directoy/splayd.log and, if not in production
-- mode, log each job's output in logs_directoy/jobs/job.log.
jobs_log = true -- Log jobs output.

-- if the trace has ended for a trace-job
job_trace_ended = {}

if production then
	exec_script = false
	SSL = true
	connect_retry_timeout = 180
	max_disconnection_time = 3600
	always_run = true
	jobs_log = false
end

if SSL then
	--ssl = require"splay.ssl"
	ssl = require"ssl" -- LuaSec
else
	socket = require"socket"
end

--[[ Splayd's settings ]]--

-- Default settings
--[[ DO YOUR SETTINGS CHANGE IN settings.lua ]]--

-- splayd already exists (from the C env)

splayd.settings = {}

splayd.settings.name = "Default Name"

splayd.settings.controller = {}
splayd.settings.controller.ip = "127.0.0.1"
splayd.settings.controller.port = 11000

splayd.settings.protocol = "standard" -- "standard OR grid, default is STANDARD"

splayd.settings.job = {}
splayd.settings.job.max_number = 16
splayd.settings.job.max_mem = 8 * 1024 * 1024 -- 8 Mo
splayd.settings.job.disk = {}
splayd.settings.job.disk.max_size = 1024 * 1024 * 1024 -- 1 Go
splayd.settings.job.disk.max_files = 1024
splayd.settings.job.disk.max_file_descriptors = 64
splayd.settings.job.disk.directory = jobs_fs_dir
splayd.settings.job.network = {}
splayd.settings.job.network.max_send = 1024 * 1024 * 1024
splayd.settings.job.network.max_receive = 1024 * 1024 * 1024
splayd.settings.job.network.max_sockets = 64
splayd.settings.job.network.max_ports = 2
splayd.settings.job.network.start_port = 22000
splayd.settings.job.network.end_port = 32000

-- Informations for the Controller only, enforce them with trickle.
splayd.settings.network = {}
splayd.settings.network.send_speed = 0
splayd.settings.network.receive_speed = 0

-- Load local settings
dofile("settings.lua")

-- Received from the controller (optionnal)
splayd.settings.log = {}
splayd.settings.log.ip = nil
splayd.settings.log.port = nil
splayd.settings.log.max_size = nil

-- command line arguments (only for testing)
if not production and arg then
	if arg[1] then splayd.settings.key = arg[1] end
	if arg[2] then splayd.settings.controller.ip = arg[2] end
	if arg[3] then splayd.settings.controller.port = tonumber(arg[3]) end
	if arg[4] then splayd.settings.job.network.start_port = tonumber(arg[4]) end
	if (arg[4] and (arg[5]==nil))
	then
		print("You need to specify a start port AND a end port")
		os.exit()
	end
	if arg[5] then splayd.settings.job.network.end_port = tonumber(arg[5]) end
	if arg[6] then splayd.settings.name = arg[6] end
end

splayd.status = {}
splayd.status.version = _SPLAYD_VERSION
splayd.status.lua_version = _VERSION
splayd.status.bits = splay.bits_detect()
splayd.status.endianness = splay.endian()

-- TODO non unices support
splayd.status.os = io.popen("uname"):read()
splayd.status.full_os = io.popen("uname -a"):read()
splayd.status.architecture = io.popen("uname -m"):read()
--  MacOS X:
-- uname: Darwin
-- uname -a:Darwin stud2066.idi.ntnu.no 9.6.0 Darwin Kernel Version 9.6.0: Mon
-- Nov 24 17:37:00 PST 2008; root:xnu-1228.9.59~1/RELEASE_I386 i386
-- 16:16  up 4 days,  5:14, 10 users, load averages: 0,11 0,15 0,22 (commas istead of dots)
-- TODO *BSDs

if splayd.status.os == "Linux" then
	splayd.status.uptime = string.gmatch(io.open("/proc/uptime"):read(), "%d+.%d+")()
	local lf = string.gmatch(io.open("/proc/loadavg"):read(), "%d+.%d+")
	splayd.status.loadavg = lf().." "..lf().." "..lf()
elseif splayd.status.os == "Darwin" then
	--now since Epoch
	local now=tonumber(os.time())
	--sysctl -n kern.boottime : { sec = 1291024934, usec = 0 } Mon Nov 29 11:02:14 2010: boot since epoch
	local boottime=tonumber(io.popen("sysctl -n kern.boottime"):read():match("sec = (%d+)"))
	splayd.status.uptime=now-boottime
	-- { 0.40 0.37 0.25 }
	splayd.status.loadavg = io.popen("sysctl -n vm.loadavg"):read():match("%d+.%d+ %d+.%d+ %d+.%d+")
else
	splayd.status.uptime = "1"
	splayd.status.loadavg = "1.0 1.0 1.0"
end


--[[ These information seems not very interesting... maybe one day.
splayd.status.ram =
splayd.status.cpu_speed =
splayd.status.nb_cpu =
--]]

--[[ Blacklist base
Note: There is no (portable) way to know all our IPs, but when a new job is
registered, it contains the list of other nodes including itself with our IP
has seen by the Controller. So when a job register, we still add his IP to the
blacklist.

If the controller is localhost, we suppose we are doing a local test and
remove restrictions.

The nodes will be able to do RPC on themself even if "localhost"
is denied using their public IP.
--]]
if splayd.settings.controller.ip ~= "127.0.0.1" and
		splayd.settings.controller.ip ~= "localhost" then

	--splayd.blacklist = {splayd.settings.controller.ip, "127.0.0.1", "localhost"}

	-- UPDATE actually we do not blacklist anymore controller IP because:
	-- 1) the controller can be a set of IPs
	-- 2) if the controller wants to blacklist its IPs, it can use the blacklist
	--	mechanism
	splayd.blacklist = {"127.0.0.1", "localhost"}
else
	splayd.blacklist = {}
end

splayd.session = ""
splayd.last_connection_time = 0


-- reference to the churn coroutine
co_churn = nil
-- reference to the server loop coroutine
co_server_loop = nil
-- so_timeout can be 0 (non-blocking socket) or nil (blocking socket)
so_timeout = nil


-- received from Controller
splayd.jobs = {}

-- table of churn jobs
splayd.churn_mgmt_jobs = {}

--[[
job.status can have the folowing values:
- waiting: Waiting to be executed.
- running: Executing.
--]]

--[[ Ready to run !!! ]]--

prepare_dir(jobs_dir)
prepare_dir(logs_dir)
prepare_dir(jobs_logs_dir)
prepare_dir(libs_cache_dir)
prepare_dir(splayd.settings.job.disk.directory)
if not check() then os.exit() end
display_config()
run()

print("Splayd shutdown.")

