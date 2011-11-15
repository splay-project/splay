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

-- JSON-RPC over HTTP client for SPLAY controller -- "SUBMIT JOB" command
-- Created by Lucas Charles

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
--for the JSON encoding/decoding
local json   = require"json" or require"lib.json"

common_lib = loadfile("./lib/common.lua")
common_lib()
-- for encoding binary files
require "base64"


--efficient sha1 for libs
crypto = require"crypto"
evp = crypto.evp
-- for compatibility with common.lua
sha1_lib = loadfile("./lib/sha1.lua")
sha1_lib()

-- END LIBRARIES
-- FUNCTIONS

function add_usage_options()
	table.insert(usage_options, "-l\tSpecify the name of the lib to submit ")
	table.insert(usage_options, "-lv\tSpecify the version of the lib to submit")
	table.insert(usage_options, "-a\tSpecify the architecture for which the lib has been built. Usually either i386, i686 or x86_64")
	table.insert(usage_options, "-o\tSpecify the os for which the lib has been built. Usually Linux or Darwin")
end
function parse_arguments()
	-- parse -l -o -a -v
	-- set lib_XX
	local i = 1
	while i<=#arg do
		if arg[i] == "-l" then
			i = i + 1
			lib_filename = arg[i]
			-- TODOtruncate the folder name from the lib
			
		elseif arg[i] == "-o" then
			i = i + 1
			lib_os = arg[i]
		elseif arg[i] == "-a" then
			i = i + 1
			lib_arch = arg[i]
		elseif arg[i] == "-lv" then
			i = i + 1
			lib_version = arg[i]
		end
		i = i + 1 
	end
	local ok = true
	if lib_filename == nil then
		print("missing parameter")
		print("filename" )
		ok = false
	elseif lib_version == nil then
		print("missing parameter")
		print("version")
		ok = false
	elseif lib_arch == nil then
		print("missing parameter")		
		print("arch ")
		ok = false
	elseif lib_os == nil then
		print("missing parameter")
		print("os")
		ok = false
	end
	if not ok then
		print_usage()
	end
end

function load_file(lib_filename)
	-- set lib_blob
	local file = io.open(lib_filename)
	if file then
		local blob = file:read("*a")
		lib_blob = blob -- maybe useless with messagepack
	else
		print("File not found !")
	end
end

function send_submit_lib(lib_filename, lib_os, lib_arch, lib_version, lib_blob, session_id)
	-- load session_id
	-- create json message 
	-- send hash first
	print(lib_filename)
	print(lib_os)
	print(lib_arch)
	print(lib_version)
	local sha1=evp.new("sha1")
	local lib_hash = sha1:digest(lib_blob)
	print("SUBMIT A LIB with sha1 ", lib_hash)
	local body = json.encode({
		method = "ctrl_api.pre_submit_lib",
		params = {lib_filename, lib_hash, lib_version, session_id}
	})
	
	local response = http.request(cli_server_url, body)
	local json_response
	if response then
		json_response = json.decode(response)
	else
		print("No response from controller, bye bye")
		os.exit()
	end
	
	if json_response.result.ok == false then
		print("Request refused by the server")
		print(json_response.result.message)
		os.exit()
	elseif json_response.result.message == "UPLOAD" then
		-- do upload the lib
		lib_blob = base64.encode(lib_blob)
		local body = json.encode({
			method = "ctrl_api.submit_lib",
			params = {lib_filename, lib_version, lib_os, lib_arch, lib_hash, lib_blob, session_id}
		})
		local response = http.request(cli_server_url, body)
		if response then
			local json_response = json.decode(response)
			print(json_response.result.message)
		else
			print("No response from the server, try splay-list-libs to see if your lib is on the controller")
		end
	end 
	-- Now the lib is in the DB
		
end
--MAIN FUNCTION:


lib_filename = nil
lib_os = nil
lib_arch = nil
lib_version = nil
lib_blob = nil
session_id = nil
command_name="splay-submit-lib"

--maximum HTTP payload size is 10MB (overriding the max 2KB set in library socket.lua)
socket.BLOCKSIZE = 10000000
load_config()

add_usage_options()

parse_arguments()

check_cli_server()

check_session_id()

load_file(lib_filename)

send_submit_lib(lib_filename, lib_os, lib_arch, lib_version, lib_blob, session_id)
