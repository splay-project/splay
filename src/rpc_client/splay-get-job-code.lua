#!/usr/bin/env lua
--[[
       Splay Client Commands ### v1.4 ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "GET JOB CODE" command
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
	table.insert(usage_options, "-o, --output-file=FILENAME\tthe code will be saved in the file FILENAME; default file is code_JOB_ID.txt")
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		if arg[i] == "--help" or arg[i] == "-h" then
			print_line(QUIET, "send \"GET JOB CODE\" command to the SPLAY CLI server; retrieves the code of a previously submitted job and saves it on the file code_\"JOB_ID\".txt\n")
			print_usage()
		--if argument is "-q" or "--quiet"
		elseif arg[i] == "--quiet" or arg[i] == "-q" then
			--the print mode is "quiet"
			print_mode = QUIET
		elseif arg[i] == "--verbose" or arg[i] == "-v" then
			--the print mode is "verbose"
			print_mode = VERBOSE
		--if argument is "-o"
		elseif arg[i] == "-o" then
			i = i + 1
			--the name of the output file is the next argument
			output_filename = arg[i]
		--if argument contains "--output-file=" at the beginning
		elseif string.find(arg[i], "^--output-file=") then
			--the name of the output file is extracted from the rest of the argument
			output_filename = string.sub(arg[i], 15)
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

--function send_get_job_code: sends a "GET JOB CODE" command to the SPLAY CLI server
function send_get_job_code(job_id, cli_server_url, session_id)
	--prints the arguments
	print_line(VERBOSE, "JOB_ID         = "..job_id)
	print_line(VERBOSE, "SESSION_ID     = "..session_id)
	print_cli_server()

	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.get_job_code",
		params = {job_id, session_id}
	})

	--prints that it is sending the message
	print_line(VERBOSE, "\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	if check_response(response) then
		local json_response = json.decode(response)
		print_line(NORMAL, "Code from JOB "..job_id.." successfully retrieved")
		if not output_filename then
			--the default output file is code_jobid.txt (e.g. for Job ID = 3, file = code_3.txt)
			output_filename = "code_"..job_id..".txt"
		end
		local f1 = io.open(output_filename,"w")
		f1:write(json_response.result.code)
		f1:close()
		print_line(NORMAL, "\nCode saved in file "..output_filename)
	end

end


--MAIN FUNCTION:
--initializes the variables
command_name = "splay_get_job_code"
other_mandatory_args = "JOB_ID "

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000

load_config()

add_usage_options()

parse_arguments()

print_line(NORMAL, "")

check_min_arg()

check_cli_server()

check_session_id()

--calls send_get_job_code
send_get_job_code(job_id, cli_server_url, session_id)

