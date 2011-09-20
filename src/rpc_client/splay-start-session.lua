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

-- JSON-RPC over HTTP client for SPLAY controller -- "START SESSION" command
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
	table.insert(usage_options, "-p, --password=PASSWD\t\tenters the password in the command line")
end

function parse_arguments()
	local i = 1
	while i<=#arg do
		--if argument is "-h" or "--help"
		if arg[i] == "--help" or arg[i] == "-h" then
			--prints a short explanation of what the program does
			print("send \"START SESSION\" command to the SPLAY CLI server; starts a session linked to a key, so the user need not type username-password at every command\n")
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
			--the password is the next argument
			password = arg[i]
		--if argument contains "--password=" at the beginning
		elseif string.find(arg[i], "^--password=") then
			--the password is the other part of the argument
			password = string.sub(arg[i], 12)
		--if argument is "-i" or "--cli_server_as_ip_addr"
		elseif arg[i] == "-i" or arg[i] == "--cli_server_as_ip_addr" then
			--Flag cli_server_as_ip_addr is true
			cli_server_as_ip_addr = true
		--if cli_server_url is not yet filled
		elseif not cli_server_url then
			--CLI server URL is the argument
			cli_server_url = arg[i]
			--all the required arguments have been filled
			min_arg_ok = true
		end
		i = i + 1
	end
end

--function send_start_session: sends a "START SESSION" command to the SPLAY CLI server
function send_start_session(username, password, cli_server_url)
	--prints the arguments
	print("USERNAME       = "..username)
	print("CLI SERVER URL = "..cli_server_url)
	
	local hashed_password = sha1(password)
	
	--prepares the body of the message
	local body = json.encode({
		method = "ctrl_api.start_session",
		params = {username, hashed_password}
	})
	
	--prints that it is sending the message
	print("\nSending command to "..cli_server_url.."...\n")

	--sends the command as a POST
	local response = http.request(cli_server_url, body)

	--if there is a response
	if check_response(response) then
		local json_response = json.decode(response)
		print("Session started:")
		print("SESSION_ID = "..json_response.result.session_id)
		print("EXPIRES_AT = "..json_response.result.expires_at.."\n")
		local hashed_cli_server_url = sha1(cli_server_url)
		local session_file = io.open("."..hashed_cli_server_url..".session_id","w")
		session_file:write(json_response.result.session_id)
		session_file:close()
	end
	
end


--MAIN FUNCTION:
--initializes the variables
username = nil
password = nil
cli_server_url = nil

cli_server_url_from_conf_file = nil
username_from_conf_file = nil
password_from_conf_file = nil

cli_server_as_ip_addr = false
min_arg_ok = false

command_name = "splay-start-session"
usage_options = {}
other_mandatory_args = ""

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

password = check_password(password, "Password")

--calls start_session
send_start_session(username, password, cli_server_url)
