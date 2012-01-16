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

-- JSON-RPC over HTTP client for SPLAY controller -- "SUBMIT LIB" command

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

function add_usage_options()
	table.insert(usage_options, "-l\tSpecify the lib name that we use to filter the list ")
end


function parse_arguments()
	local i = 1
	if #arg > 0 then
		if arg[i] == "-l" then
			i = i + 1
			lib_name = arg[i]
		else
			print_usage()
		end
	else
		lib_name=""
	end
end
function send_list_libs(cli_server_url, lib_name, session_id)
	
	print("SESSION_ID     = "..session_id)
	print("CLI SERVER URL = "..cli_server_url)
	print("LIB NAME = "..lib_name)
	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.list_libs",
		params = {lib_name, session_id}
	})
	
	--prints that it is sending the message
	print("\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)
	
	if check_response(response) then
		local json_response = json.decode(response)
		print("Libs list : number of items "..#json_response.result.libs_list)
		for _,v in ipairs(json_response.result.libs_list) do
			print("Lib name ="..v.lib_name.." Version="..v.lib_version.." Arch="..v.lib_arch.." OS="..v.lib_os.." SHA1="..v.lib_sha1)
		end
	end
end
--MAIN FUNCTION:
--initializes the variables
cli_server_url = nil
session_id = nil
lib_name = ""
cli_server_url_from_conf_file = nil

cli_server_as_ip_addr = false
min_arg_ok = false

command_name = "splay_list_libs"
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

--check_min_arg()

check_cli_server()

check_session_id()

--calls send_list_splayds
send_list_libs(cli_server_url, lib_name, session_id)
