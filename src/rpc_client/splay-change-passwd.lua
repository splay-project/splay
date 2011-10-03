#!/usr/bin/env lua
--[[
       Splay Client Commands ### v1.2 ###
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

-- JSON-RPC over HTTP client for SPLAY controller -- "CHANGE PASSWORD" command
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
	table.insert(usage_options, "-u, --username=USERNAME\t\tenters the username in the command line")
	table.insert(usage_options, "-p, --current_password=PASSWD\tenters the current password in the command line")
	table.insert(usage_options, "-n, --new_password=PASSWD\tenters the new password in the command line")
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		--if argument is "-h" or "--help"
		if arg[i] == "--help" or arg[i] == "-h" then
			--prints a short explanation of what the program does
			print("send \"CHANGE PASSWORD\" command to the SPLAY CLI server; changes the password of a given user\n")
			--prints the usage
			print_usage()
			--if argument is "-u"
		elseif arg[i] == "-u" then
			i = i + 1
			--the username is the next argument
			username = arg[i]
		--if argument contains "--username=" at the beginning
		elseif string.find(arg[i], "^--username=") then
			--the username is the other part of the argument
			username = string.sub(arg[i], 12)
		--if argument is "-p"
		elseif arg[i] == "-p" then
			i = i + 1
			--the current password is the next argument
			current_password = arg[i]
		--if argument contains "--current_password=" at the beginning
		elseif string.find(arg[i], "^--current_password=") then
			--the current password is the other part of the argument
			current_password = string.sub(arg[i], 12)
		--if argument is "-n"
		elseif arg[i] == "-n" then
			i = i + 1
			--the new password is the next argument
			new_password = arg[i]
		--if argument contains "--new_password=" at the beginning
		elseif string.find(arg[i], "^--new_password=") then
			--the current password is the other part of the argument
			new_password = string.sub(arg[i], 12)
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag rpc_as_ip_addr is true
			rpc_as_ip_addr = true
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

--function send_change_passwd: sends a "CHANGE PASSWORD" command to the SPLAY CLI server
function send_change_passwd(username, current_password, new_password, cli_server_url)
	--prints the arguments
	print_username("USERNAME       ", username)
	print_cli_server()

	local hashed_currentpassword = sha1(current_password)
	local hashed_newpassword = sha1(new_password)

	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.change_passwd",
		params = {username, hashed_currentpassword, hashed_newpassword}
	})


	--prints that it is sending the message
	print("\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	--if there is a response
	if check_response(response) then
		print("Password changed\n")
	end

end


--MAIN FUNCTION:
--initializes the variables
current_password = nil
new_password = nil
command_name = "splay-change-passwd"

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

username = check_username(username, "Username")

current_password = check_password(current_password, "Current password")

new_password = check_password(new_password, "New password")

--calls send_change_passwd
send_change_passwd(username, current_password, new_password, cli_server_url)

