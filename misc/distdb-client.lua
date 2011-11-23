#!/usr/bin/env lua
-- Client for the Splay Distributed DB Module
-- Created by José Valerio
-- Neuchâtel 2011

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
local ltn12  = require"ltn12"
--for hashing
require"crypto"
--for picking a random port
misc = require"splay.misc"
local json = require"json"
events = require"splay.events"

-- END LIBRARIES

-- FUNCTIONS

function send_put(port, type_of_transaction, key, value)
	local response_body = nil
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	local value_str = ""..value

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://127.0.0.1:"..port.."/"..key,
		method = "PUT",
		headers = {
			["Type"] = type_of_transaction,
			["Content-Length"] = string.len(value_str),
			["Content-Type"] =  "plain/text"
			},
		source = ltn12.source.string(value_str),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		print("PUT done.")
	else
		print("Error "..response_status)
	end
end

function send_get(port, type_of_transaction, key)

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://127.0.0.1:"..port.."/"..key,
		method = "GET",
		headers = {
			["Type"] = type_of_transaction
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		print("Content of kv-store: "..key.." is:\n"..response_body[1])
	else
		print("Error "..response_status..":\n"..response_body[1])
	end

	local answer = json.decode(response_body[1])

	local chosen_value = 0
	local max_vc = {}
	for i2,v2 in ipairs(answer) do
		if v2.value > chosen_value then --in this case is the max, but it could be other criteria
			chosen_value = v2.value
		end
		for i3,v3 in pairs(v2.vector_clock) do --NOTE i dont get this 100%, what if the client application wants to fuck up the versions?
			if not max_vc[i3] then
				max_vc[i3] = v3
			elseif max_vc[i3] < v3 then
				max_vc[i3] = v3
			end
		end
	end
	print("key: "..key..", value: "..chosen_value..", merged vector_clock:")
	for i2,v2 in pairs(max_vc) do
		print("", i2, v2)
	end
	return chosen_value, max_vc
end
events.run(function()
	dofile("ports.lua")
	math.randomseed(os.time())
	local key = crypto.evp.digest("sha1",math.random(100000))

	for i=1, 4 do
		local port = misc.random_pick(ports)
		print("Key is "..key)
--		send_put(port, "evtl_consistent", key, i*10)
--		send_put(port, "consistent", key, i*10)
		send_put(port, "paxos", key, i*10)
		events.sleep(1)
	end

	for i=1, 1 do
		local port = misc.random_pick(ports)
--		send_get(port, "evtl_consistent", key)
--		send_get(port, "consistent", key)
		send_get(port, "paxos", key)
		events.sleep(1)
	end
end)

