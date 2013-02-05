-- Client for the Splay Distributed DB Module
--To be used as library
-- Created by José Valerio
-- Neuchâtel 2011-2012

-- BEGIN LIBRARIES
--for the communication over HTTP
local socket = require"socket"
local http   = require"socket.http"
local ltn12  = require"ltn12"
local serializer = require"splay.lbinenc"
--logger provides some fine tunable logging functions
local logger = require"logger"
-- END LIBRARIES

_LOCAL = true

socket.BLOCKSIZE = 10000000

--to be used as RAM storage (_LOCAL mode)
local kv_records = {}


--FUNCTIONS

function send_command(command_name, url, key, type_of_transaction, value)
	--initializes the logger
	local log1 = new_logger(".DIST_DB_CLIENT send_command")
	--logs entrance in the function
	log1:logprint("START")
	log1:logprint("", "", "url="..url..", key="..key..", type_of_transaction="..type_of_transaction..", value="..value)
	--response_body will contain the returning data from the web-service call
	local response_body = {}
	--request_source contains the input data
	local request_source = nil
	--request_headers is a table that contains the HTTP request headers
	local request_headers = {}
	--if the command brings a value
	if value then
		--request_source is a LTN12 object based on a string
		request_source = ltn12.source.string(tostring(value))
		--headers Content-Length and Content-Type are filled
		request_headers["Content-Length"] = string.len(tostring(value))
		request_headers["Content-Type"] =  "plain/text"
	--if value is empty
	else
		--request_source is an empty LTN12 object
		request_source = ltn12.source.empty()
	end

	--if type_of_transaction is specified
	if type_of_transaction then
		--header Type is filled with it
		request_headers["Type"] = type_of_transaction
	end

	--makes the HTTP request
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..(key or ""),
		method = command_name,
		headers = request_headers,
		source = request_source,
		sink = ltn12.sink.table(response_body)
	})

	--if the response is not a 200 OK
	if response_status ~= 200 then
		--logs the error
		log1:logprint("END ERROR", "response_status="..response_status)
		--flushes all logs
		log1:logflush()
		--returns false and the error
		return false, response_status
	end

	--if it arrives here, it means it didn't enter inside the if
	log1:logprint("", "200 OK received")
	--logs END of the function
	log1:logprint("END", "", "result_mode="..result_mode)
	--flushes all logs
	log1:logflush()
	--if there is a response_body
	if type(response_body) == "table" and response_body[1] then
		--returns true (indicates a succesful call), and the return value
		return true, serializer.decode(response_body[1])
	end
	--if there was no response body, returns only "true"
	return true
end

--function send_get
function send_get(url, key, type_of_transaction)
	--initializes the logger
	local log1 = new_logger(".DIST_DB_CLIENT send_get")
	--logs START of the function
	log1:logprint("START")
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--logs END of the function
		log1:logprint("END", "local storage")
		--flushes all logs
		log1:logflush()
		--returns true and the value
		return true, kv_records[key]
	end

	local get_ok, answer = send_command("GET", url, key, type_of_transaction)
	
	local chosen_value = nil

	if not get_ok then
		return false
	end

	if (not answer) or (not answer[1]) then
		return true, nil
	end

	if type(answer[1].value) == "string" then
		chosen_value = ""
		log1:logprint("", "value is string")
	elseif type(answer[1].value) == "number" then
		chosen_value = 0
	elseif type(answer[1].value) == "table" then
		log1:logprint("", "value is a table")
	end

	--for evtl_consistent get
	local max_vc = {}
	for i2,v2 in ipairs(answer) do
		log1:logprint("RAW_DATA", "value="..v2.value)
		log1:logprint("RAW_DATA", "chosen_value="..chosen_value)
		if type(v2.value) == "string" then
			if string.len(v2.value) > string.len(chosen_value) then --in this case is the max length, but it could be other criteria
				log1:logprint("", "replacing value")
				chosen_value = v2.value
			end
		elseif type(v2.value) == "number" then
			if v2.value > chosen_value then --in this case is the max, but it could be other criteria
				log1:logprint("", "replacing value")
				chosen_value = v2.value
			end
		end
		
		for i3,v3 in pairs(v2.vector_clock) do --NOTE i dont get this 100%, what if the client application wants to fuck up the versions?
			if not max_vc[i3] then
				max_vc[i3] = v3
			elseif max_vc[i3] < v3 then
				max_vc[i3] = v3
			end
		end
	end
	--logs END of the function
	log1:logprint("END", "", "key="..key..", value="..chosen_value..", merged vector_clock="..table2str("max_vc", 0, max_vc))
	--flushes all logs
	log1:logflush()
	return true, chosen_value, max_vc
end

--function send_put
function send_put(url, key, type_of_transaction, value)
	--initializes the logger
	local log1 = new_logger(".DIST_DB_CLIENT send_put")
	--logs START of the function
	log1:logprint("START", "", "key="..key)
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--logs END of the function
		log1:logprint("END", "local storage")
		--flushes all logs
		log1:logflush()
		kv_records[key] = value
		return true
	end
	--logs END of the function
	log1:logprint("END")
	--flushes all logs
	log1:logflush()
	return send_command("PUT", url, key, type_of_transaction, value)
end

function send_del(url, key, type_of_transaction)
	--initializes the logger
	local log1 = new_logger(".DIST_DB_CLIENT send_del")
	--logs START of the function
	log1:logprint("START")
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--logs END of the function
		log1:logprint("END", "local storage")
		--flushes all logs
		log1:logflush()
		kv_records[key] = nil
		return true
	end
	--logs END of the function
	log1:logprint("END")
	--flushes all logs
	log1:logflush()
	return send_command("DELETE", url, key, type_of_transaction)
end

function send_get_node_list(url)
	--logprint("DIST_DB_CLIENT", "send_get_node_list: START.")
	local send_ok, node_list = send_command("GET_NODE_LIST", url)
	--logprint("DIST_DB_CLIENT", "send_get_node_list:")
	--logprint("DIST_DB_CLIENT", table2str("node_list", 0, node_list))
	--logprint("DIST_DB_CLIENT", "send_get_node_list: END.")
	return send_ok, node_list
end

function send_get_key_list(url)
	--logprint("DIST_DB_CLIENT", "send_get_key_list: START.")
	local send_ok, key_list = send_command("GET_KEY_LIST", url)
	--logprint("DIST_DB_CLIENT", "send_get_key_list:")
	--logprint("DIST_DB_CLIENT", table2str("key_list", 0, key_list))
	--logprint("DIST_DB_CLIENT", "send_get_key_list: END.")
	return send_ok, key_list
end

function send_get_master(url, key)
	--logprint("DIST_DB_CLIENT", "send_get_master: START.")
	return send_command("GET_MASTER", url, key)
end

function send_get_all_records(url)
	--logprint("DIST_DB_CLIENT", "send_get_all_records: START.")
	return send_command("GET_ALL_RECORDS", url)
end

function send_change_log_lvl(url, log_level)
	--logprint("DIST_DB_CLIENT", "send_change_log_lvl: START.")
	return send_command("CHANGE_LOG_LVL", url, log_level)
end