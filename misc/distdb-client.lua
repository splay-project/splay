-- Client for the Splay Distributed DB Module - Asynchronous Version (Uses splay.events)
-- To be used as library
-- Created by José Valerio
-- Neuchâtel 2011-2012

-- BEGIN LIBRARIES
--for the synchronous HTTP client
local socket = require"socket"
local http   = require"socket.http"
local ltn12  = require"ltn12"
--for the asynchronous HTTP client
local async_http = require"prosody.http"
-- splay.lbinenc handles native encoding/decoding for HTTP messages
local serializer = require"splay.lbinenc"
--logger provides some fine tunable logging functions
require"logger"
-- END LIBRARIES

_LOCAL = false

socket.BLOCKSIZE = 10000000

--to be used as RAM storage (_LOCAL mode)
local kv_records = {}
--the mini proxy handles asynchronous put
local mini_proxy_ip = "127.0.0.1"
local mini_proxy_port = 33500


--FUNCTIONS

--SYNCHRONOUS DB OPERATIONS

--function send_command: sends a command to the Entry Point
function send_command(command_name, url, resource, sync_mode, consistency, value)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_command", "INPUT", "command name="..command_name..", URL="..url..", resource="..tostring(resource)
		..", Synchronization Mode="..tostring(sync_mode)..", consistency="..tostring(consistency))
	--prints the value
	log1:logprint(".RAW_DATA", "INPUT", "value="..(value or "nil"))
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

	--if consistency is specified. TODO: test if the "if" statement can be deleted
	if consistency then
		--header Type is filled with it. TODO: change the name of the header to "Consistency"
		request_headers["Type"] = consistency
	end

	--fills the header Sync-Mode ("sync" is the default)
	request_headers["Sync-Mode"] = sync_mode or "sync"
	
	--makes the HTTP request
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..(resource or ""),
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
	--logs END of the function and flushes all logs
	log1:logprint("END")
	--if there is a response_body
	if type(response_body) == "table" and response_body[1] then
		log1:logprint(".TABLE", tbl2str("Response Body", 0, serializer.decode(response_body[1])))
		--returns true (indicates a succesful call), and the return value
		return true, serializer.decode(response_body[1])
	end
	--if there was no response body, returns only "true"
	return true
end

--function send_get: sends a "GET" command to the Entry Point, then merges vector clocks if necessary
function send_get(url, key, consistency)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_get", "INPUT", "url="..tostring(url)..", key="..tostring(key)..", Consistency Model="..tostring(consistency))
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true and the value
		return true, kv_records[key]
	end

	local ok, answer = send_command("GET", url, key, "sync", consistency)
	
	local chosen_value = nil

	if not ok then
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
		log1:logprint(".RAW_DATA", "value="..(v2.value or "nil"))
		log1:logprint(".RAW_DATA", "chosen_value="..(chosen_value or "nil"))
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
	log1:logprint(".RAW_DATA", "value="..(chosen_value or "nil"))
	log1:logprint(".TABLE", tbl2str("merged VC", 0, max_vc))
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns true, the value and the merged vector clock
	return true, chosen_value, max_vc
end

--function send_put: sends a "PUT" command to the Entry Point
function send_put(url, key, sync_mode, consistency, value)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_put", "INPUT", "url="..tostring(url)..", key="..tostring(key)
		..", Synchronization Mode="..tostring(sync_mode)..", Consistency Model="..tostring(consistency))
	--logs
	log1:logprint(".RAW_DATA", "INPUT", "value=\""..value.."\"")
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--sets the value
		kv_records[key] = value
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true
		return true
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "calling send_command")
	--calls send_command("PUT") and returns the results
	return send_command("PUT", url, key, sync_mode, consistency, value)
end

--function send_del: sends a "DEL" command to the Entry Point
function send_del(url, key, sync_mode, consistency)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_del", "INPUT", "url="..tostring(url)..", key="..tostring(key)
		..", Synchronization Mode="..tostring(sync_mode)..", Consistency Model="..tostring(consistency))
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--deletes the record
		kv_records[key] = nil
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true
		return true
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "calling send_command")
	--returns the result of send_command
	return send_command("DEL", url, key, sync_mode, consistency)
end

--function send_get_nodes: alias to send_command("GET_NODES")
function send_get_nodes(url)
	return send_command("GET_NODES", url)
end

--function send_get_keys: alias to send_command("GET_KEYS")
function send_get_keys(url)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_del", "INPUT", "url="..tostring(url))
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		local keys = {}
		for i,v in pairs(kv_records) do
			table.insert(keys, i)
			log1:logprint("", "key="..i)
		end
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true and the list of keys
		return true, keys
	end
	--logs END of the function and flushes all logs
	log1:logprint_flush("END", "calling send_command")
	--returns the result of send_command
	return send_command("GET_KEYS", url)
end

--function send_get_master: alias to send_command("GET_MASTER")
function send_get_master(url, key)
	return send_command("GET_MASTER", url, key)
end

--function send_get_all: alias to send_command("GET_ALL")
function send_get_all(url)
	return send_command("GET_ALL", url)
end

--function send_del_all: alias to send_command("DEL_ALL")
function send_del_all(url)
	return send_command("DEL_ALL", url)
end

--function send_set_log_lvl: alias to send_command("SET_LOG_LVL")... key is nil
function send_set_log_lvl(url, log_level)
	return send_command("SET_LOG_LVL", url, nil, "sync", nil, log_level)
end

--function send_set_rep_params: alias to send_command("SET_REP_PARAMS")... key is nil
function send_set_rep_params(url, n_replicas, min_replicas_read, min_replicas_write)
	local rep_params = {n_replicas, min_replicas_read, min_replicas_write}
	return send_command("SET_REP_PARAMS", url, nil, "sync", nil, serializer.encode(rep_params))
end

--ASYNCHRONOUS DB OPERATIONS

--function send_async_put: sends a "PUT" command to the Entry Point (asynchronous mode)
function send_async_put(tid, url, key, consistency, value)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_async_put", "INPUT", "tid="..tid..", url="..tostring(url)..", key="..tostring(key)..", Consistency Model="..tostring(consistency))
	--logs
	log1:logprint(".RAW_DATA", "INPUT", "value=\""..value.."\"")
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--sets the value
		kv_records[key] = value
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true
		return true
	end
	--opens a new socket
	local sock1 = socket.tcp()
	--tries to connect to the mini proxy
	sock1:connect(mini_proxy_ip, mini_proxy_port)
	--send the PUT command through raw TCP
	sock1:send("PUT "..tid.." "..url.." "..key.." "..consistency.." "..value:len().."\n"..value)
	--waits for the answer (the proxy answers as soon as the PUT command is received)
	local answer = sock1:receive()
	--closes the socket
	sock1:close()
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--if the answer is OK returns true, if it is anything else, returns false
	if answer == "OK" then
		return true
	else
		return false
	end
end

--function send_async_del: sends a "DEL" command to the Entry Point (asynchronous mode)
function send_async_del(tid, url, key, consistency)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_async_del", "INPUT", "tid="..tid..", url="..tostring(url)..", key="..tostring(key)..", Consistency Model="..tostring(consistency))
	--if the transaction is local (bypass distributed DB)
	if _LOCAL then
		--sets the value
		kv_records[key] = value
		--logs END of the function and flushes all logs
		log1:logprint_flush("END", "using local storage")
		--returns true
		return true
	end
	--opens a new socket
	local sock1 = socket.tcp()
	--tries to connect to the mini proxy
	sock1:connect(mini_proxy_ip, mini_proxy_port)
	--send the PUT command through raw TCP
	sock1:send("DEL "..tid.." "..url.." "..key.." "..consistency.." 0")
	--waits for the answer (the proxy answers as soon as the PUT command is received)
	local answer = sock1:receive()
	--closes the socket
	sock1:close()
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--if the answer is OK returns true, if it is anything else, returns false
	if answer == "OK" then
		return true
	else
		return false
	end
end

--function send_ask_tids: asks the proxy if some TIDs are still open
function send_ask_tids(tid_list)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_ask_tids")
	--logs
	log1:logprint(".TABLE", "INPUT", tbl2str("tid_list", 0, tid_list))
	--retrieves new socket
	local sock1 = socket.tcp()
	--tries to connect to the mini proxy
	sock1:connect(mini_proxy_ip, mini_proxy_port)
	--sends the list of TIDs to the mini proxy
	local i,j = sock1:send(table.concat(tid_list, " ").."\n")
	--waits for the answer (the proxy answers as soon as the PUT command is received)
	local answer = sock1:receive()
	--closes the socket
	sock1:close()
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns the answer
	return answer
end

--function send_get_tids_status: asks if some TIDs are still open
function send_get_tids_status(url, tid_list)
	--starts the logger
	local log1 = start_logger(".DIST_DB_CLIENT send_get_tids_status", "INPUT", "URL="..url)
	--logs
	log1:logprint(".TABLE", "INPUT", tbl2str("tid_list", 0, tid_list))
	--logs END of the function and flushes all logs
	log1:logprint_flush("END")
	--returns the answer
	return send_command("GET_TIDS_STATUS", url, nil, "sync", nil, serializer.encode(tid_list))
end