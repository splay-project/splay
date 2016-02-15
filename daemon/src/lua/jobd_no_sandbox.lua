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
This program is normally called by splayd, but you can too run it standalone
to replay a job or to debug.
]]

require"table"
require"math"
require"os"
require"string"
require"io"

require"splay"
require"json"
gettimeofday=splay.gettimeofday
do
	local p = print
	print = function(...)
		--p(...)
		local s,u=gettimeofday()--splay.gettimeofday()
		p(s,u, ...) --local timestamp, used when controller configured with UseSplaydTimestamps
		io.flush()
	end
end

if not splayd then
	job_file = arg[1]
end

if not job_file then
	print("You need to give a job file parameter.")
	os.exit()
end

--print("Jobd start, job file: "..job_file)

if not splayd then
	print(">> WARNING: Lua execution, memory limit for jobs will not be enforced.")
end

f = io.open(job_file)
if not f then
	print("Error reading job data")
	os.exit()
end
--print(f:read("*a"))
job = json.decode(f:read("*a"))
f:close()

if not job then
	print("Invalid job file format.")
	os.exit()
end

if job.topology then
        local t_f=io.open(job.topology)
        local t_raw=t_f:read("*a")
        t_f:close()
        job.topology = json.decode(t_raw)
end

if job.remove_file then
	os.execute("rm -fr "..job_file.." > /dev/null 2>&1")
end

-- back to global
_SPLAYD_VERSION = job._SPLAYD_VERSION

-- Set process memory limit
if job.max_mem ~= 0 then
	if splayd then
		splayd.set_max_mem(job.max_mem)
	else
		print("Cannot apply memory limitations (run from C daemon).")
		os.exit()
	end
end

-- aliases (job.me is already prepared by splayd)
if job.network.list then
	--read the path of the file, deserialize, and replace it with the same field
	local l_f=io.open(job.network.list)
	local l_json=l_f:read("*a")
	l_f:close()
	job.network.list = json.decode(l_json)
	
	job.position = tonumber(job.network.list.position)
	
	job.nodes = job.network.list.nodes 

    job.get_live_nodes = function()
            -- if there is a timeline (trace_alt type of job)
            if job.network.list.timeline then
                    -- time since the start of the job
                    local elapsed_time = os.time() - job.network.list.start_time
                    local live_nodes = {}
                    -- initializes the event index (will hold the time on the timeline)
                    local event_index = 0
                    for i,v in ipairs(job.network.list.timeline) do
                            -- if the time is bigger or equal to the elapsed_time
                            if not (v.time < elapsed_time) then
                                    -- if the time is strictly bigger
                                    if v.time > elapsed_time then
                                            -- takes the time before this one
                                            event_index = i-1
                                    else
                                            -- takes that time
                                            event_index = i
                                    end
                                    -- stop looking
                                    break
                            end
                    end
                    -- if event index is bigger than 0
                    if event_index > 0 then
                            -- insert all nodes in the list of current nodes
                            for _,v in ipairs(job.network.list.timeline[event_index].nodes) do
                                    table.insert(live_nodes, {position=v, ip=job.network.list.nodes[v].ip, port=job.network.list.nodes[v].port})
                            end
                    end
                    return live_nodes
            -- if there is no timeline, it is a normal job, returns job.network.list.nodes
            else
                    return job.network.list.nodes
            end
    end

	job.list_type = job.network.list.type -- head, random
end
package.cpath = package.cpath..";"..job.disk.lib_directory.."/?.so"

print(">> Job settings:")
print("Ref: "..job.ref)
print("Name: "..job.name)
print("Description: "..job.description)
print("Disk:")
print("", "max "..job.disk.max_files.." files")
print("", "max "..job.disk.max_file_descriptors.." file descriptors")
print("", "max "..job.disk.max_size.." size in bytes")

print("", "lib directoy ".. job.disk.lib_directory)
print("", "cpath : "..package.cpath)
print("Mem "..job.max_mem.." bytes of memory")
print("Network:")
print("", "max "..job.network.max_send.."/"..
		job.network.max_receive.." send/receive bytes")
print("", "max "..job.network.max_sockets.." tcp sockets")
print("", "ip "..job.me.ip)
if job.network.nb_ports > 0 then
	print("", "ports "..job.me.port.."-"..(job.me.port + job.network.nb_ports - 1))
else
	print("", "no ports")
end
if job.log and job.log.max_size then
	print("Max log size: "..job.log.max_size)
end
print()

-- To test text files or bytecode files.
--file = io.open("test_job.luac", "r")
--job.code = file:read("*a")
--file:close()
--file = io.open("out.luac", "w")
--file:write(job.code)
--file:close()

-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

--[[ Restricted Socket ]]--

-- We absolutly need to load restricted_socket BEFORE any library that can use
-- LuaSocket because the library could, if we don't do that, have a local copy
-- of original, non wrapped, (or non configured) socket functions.
socket = require"socket.core"

rs = require"splay.restricted_socket"
settings = job.network
settings.blacklist = job.blacklist
settings.start_port = job.me.port
settings.end_port = job.me.port + job.network.nb_ports - 1
-- If our IP seen by the controller is 127.0.0.1, it's a local experiment and we
-- disable the port range restriction because we need to contact other splayd on
-- the same machine.
if job.me.ip ~= "127.0.0.1" then
	settings.local_ip = job.me.ip
end
rs.init(settings)

socket = rs.wrap(socket)

-- Replace socket.core, unload the other
package.loaded['socket.core'] = socket

-- This module requires debug, not allowed in sandbox
require"splay.coxpcall"


splay_code_function, err = loadstring(job.code, "job code")
job.code = nil -- to free some memory
collectgarbage("collect")
collectgarbage("collect")
if splay_code_function then
	splay_code_function()
else
	print("Error loading code:", err)
end
