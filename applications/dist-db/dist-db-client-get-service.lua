#!/usr/bin/env lua
-- Client for the Splay Distributed DB
-- Created by José Valerio
-- Neuchâtel 2011

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
local ltn12  = require"ltn12"
--for hashing
require"sha1"
--for picking a random port
misc = require"splay.misc"

-- END LIBRARIES

-- FUNCTIONS

function send_get_service(access_key_id, port)
	
	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://127.0.0.1:"..port.."/",
		method = "GET",
		headers = {
			["Host"] = "splay-project.org",
			["Authorization"] = access_key_id
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		print("Content of service for user: "..access_key_id.." is:\n"..response_body[1])
	else
		print("Error "..response_status..":\n"..response_body[1])
	end
end

dofile("ports.lua")
math.randomseed(os.time())
if arg[2] then
	port = arg[2]
else
	port = misc.random_pick(ports)
end
send_get_service(arg[1], port)

