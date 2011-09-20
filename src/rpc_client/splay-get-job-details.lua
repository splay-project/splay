#!/usr/bin/env lua
--[[
       Splay Client Commands ### v ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "GET JOB DETAILS" command
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
			print("send \"GET JOB DETAILS\" command to the SPLAY RPC server; retrieves details about a previously submitted job and prints them on the screen\n")
			print_usage()
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag cli_server_as_ip_addr is true
			cli_server_as_ip_addr = true
		elseif not job_id then
			job_id = arg[i]
			--if the cli_server_url was filled on the config file
			if cli_server_url_from_conf_file then
				--all the required arguments have been filled
				min_arg_ok = true
			end
		elseif not cli_server_url then
			cli_server_url = arg[i]
			min_arg_ok = true
		end
		i = i + 1
	end
end

--function send_get_job_details: sends a "GET JOB DETAILS" command to the SPLAY CLI server
function send_get_job_details(job_id, cli_server_url, session_id)
	--prints the arguments
	print("JOB_ID         = "..job_id)
	print("SESSION_ID     = "..session_id)
	print("CLI SERVER URL = "..cli_server_url)

	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.get_job_details",
		params = {job_id, session_id}
	})

	--prints that it is sending the message
	print("\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	if check_response(response) then
		local json_response = json.decode(response)
		if json_response.result.name then
			print("Name        = "..json_response.result.name)
		else
			print("Name        = ")
		end
		if json_response.result.description then
			print("Description = "..json_response.result.description)
		else
			print("Description = ")
		end
		print("Ref         = "..json_response.result.ref)
		print("Status      = "..json_response.result.status)
		if json_response.result.user_id then
			print("User ID     = "..json_response.result.user_id)
		end
		print("Host list = ")
		for _,v in ipairs(json_response.result.host_list) do
			print("\tsplayd_id="..v.splayd_id..", ip="..v.ip..", port="..v.port)
		end
		print()
	end
	
end


--MAIN FUNCTION:
--initializes the variables
job_id = nil
cli_server_url = nil
session_id = nil

cli_server_url_from_conf_file = nil

cli_server_as_ip_addr = false
min_arg_ok = false

command_name = "splay_get_job_details"
other_mandatory_args = "JOB_ID "
usage_options = {}

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000

load_config()

add_usage_options()

print()

parse_arguments()

check_min_arg()

check_cli_server()

check_session_id()

--calls send_get_job_details
send_get_job_details(job_id, cli_server_url, session_id)
