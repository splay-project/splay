#!/usr/bin/env lua
--[[
       Splay Client Commands ### v1.1 ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "LIST JOBS" command
-- Created by José Valerio

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
--for the JSON encoding/decoding
local json   = require"json" or require"lib.json"
--for hashing
sha1_lib = loadfile("./lib/sha1.lua")
sha1_lib()
common_lib = loadfile("./lib/common.lua")
common_lib()
-- END LIBRARIES

-- FUNCTIONS

function add_usage_options()
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		if arg[i] == "--help" or arg[i] == "-h" then
			print("send \"LIST JOBS\" command to the SPLAY CLI server; lists all jobs submitted by the user, or all if the user is an administrator\n")
			print_usage()
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag cli_server_as_ip_addr is true
			cli_server_as_ip_addr = true
		elseif not cli_server_url then
			cli_server_url = arg[i]
			min_arg_ok = true
		end
		i = i + 1
	end
end

--function send_list_jobs: sends a "LIST JOBS" command to the SPLAY CLI server
function send_list_jobs(cli_server_url, session_id)
	--prints the arguments
	print("SESSION_ID     = "..session_id)
	print("CLI SERVER URL = "..cli_server_url)

	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.list_jobs",
		params = {session_id}
	})
	
	--prints that it is sending the message
	print("\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)
	
	if check_response(response) then
		local json_response = json.decode(response)
		--counters for totals
		local stats = {
			LOCAL = 0,
			REGISTERING = 0,
			RUNNING = 0,
			ENDED = 0,
			NO_RESSOURCES = 0,
			REGISTER_TIMEOUT = 0,
			KILLED = 0,
                        QUEUED = 0	-- raluca: No. jobs that are queued, waiting for resources
		}
		--prints the result
		print("Job List =")
		for _,v in ipairs(json_response.result.job_list) do
			if v.user_id then
				print("\tjob_id="..v.id..", user_id="..v.user_id..", status="..v.status)
			else
				print("\tjob_id="..v.id..", status="..v.status)
			end
			stats[v.status] = stats[v.status] + 1
		end
		print("\nTotals =")
		for k,v in pairs(stats) do
			print(k.." = "..v.." ")
		end
		print()
	end
	
end


--MAIN FUNCTION:
--initializes the variables
cli_server_url = nil
session_id = nil

cli_server_url_from_conf_file = nil

cli_server_as_ip_addr = false
min_arg_ok = false

command_name = "splay_list_jobs"
other_mandatory_args = ""
usage_options = {}

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000

load_config()
--if the CLI server was loaded from the config file
if cli_server_url_from_conf_file then
	--minimum arguments are filled
	min_arg_ok = true
end

add_usage_options()

print()

parse_arguments()

check_min_arg()

check_cli_server()

check_session_id()

--calls send_list_jobs
send_list_jobs(cli_server_url, session_id)
