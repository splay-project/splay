#!/usr/bin/env lua
--[[
       Splay Client Commands ### v1.3 ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "LIST USERS" command
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
	table.insert(usage_options, "-U, --admin_username=ADM_UNAME\tenters the administrator's username in the command line")
	table.insert(usage_options, "-P, --admin_password=ADM_PASSWD\tenters the administrator's password in the command line")
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		if arg[i] == "--help" or arg[i] == "-h" then
			print_line(QUIET, "send \"LIST USERS\" command to the SPLAY CLI server; lists all SPLAY users (only for Administrators)\n")
			print_usage()
		--if argument is "-U"
		--if argument is "-q" or "--quiet"
		elseif arg[i] == "--quiet" or arg[i] == "-q" then
			--the print mode is "quiet"
			print_mode = QUIET
		elseif arg[i] == "--verbose" or arg[i] == "-v" then
			--the print mode is "verbose"
			print_mode = VERBOSE
		elseif arg[i] == "-U" then
			i = i + 1
			--the Administrator's username is the next argument
			admin_username = arg[i]
		--if argument contains "--admin_username=" at the beginning
		elseif string.find(arg[i], "^--admin_username=") then
			--the Administrator's username is the other part of the argument
			admin_username = string.sub(arg[i], 18)
		--if argument is "-P"
		elseif arg[i] == "-P" then
			i = i + 1
			--the Administrator's password is the next argument
			admin_password = arg[i]
		--if argument contains "--admin_password=" at the beginning
		elseif string.find(arg[i], "^--admin_password=") then
			--the Administrator's password is the other part of the argument
			admin_password = string.sub(arg[i], 18)
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag cli_server_as_ip_addr is true
			cli_server_as_ip_addr = true
		--if cli_server_url is not yet filled
		elseif not cli_server_url then
			--RPC server URL is the argument
			cli_server_url = arg[i]
			--all the required arguments have been filled
			min_arg_ok = true
		end
		i = i + 1
	end
end

--function send_list_users: sends a "LIST USERS" command to the SPLAY CLI server
function send_list_users(cli_server_url, admin_username, admin_password)
	--prints the arguments
	print_username("ADMIN USERNAME   ", admin_username)
	print_cli_server(3)

	local admin_hashedpassword = sha1(admin_password)

	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.list_users",
		params = {admin_username, admin_hashedpassword}
	})

	--prints that it is sending the message
	print_line(VERBOSE, "\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	if check_response(response) then
		local json_response = json.decode(response)
		print_line(NORMAL, "User List =")
		for _,v in ipairs(json_response.result.user_list) do
			print_line(QUIET, "\tid="..v.id..", username="..v.username)
		end
		print_line(NORMAL, "")
	end

end


--MAIN FUNCTION:
--initializes the variables
command_name = "splay-list-users"

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000

load_config()

--if the CLI server was loaded from the config file
if cli_server_url_from_conf_file then
	--minimum arguments are filled
	min_arg_ok = true
end

add_usage_options()

parse_arguments()

print_line(NORMAL, "")

check_min_arg()

check_cli_server()

admin_username = check_username(admin_username, "Administrator's username")

admin_password = check_password(admin_password, "Administrator's password")

--calls send_list_users
send_list_users(cli_server_url, admin_username, admin_password)

