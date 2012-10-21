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
local rpcq = require"splay.rpcq"
-- END LIBRARIES

_LOGMODE = "none"
_LOGFILE = "/home/unine/Desktop/logfusesplay/log.txt"
local log_tbl = {}

socket.BLOCKSIZE = 10000000

-- FUNCTIONS

function table2str(name, order, input_table)
	--creates a table to store all strings; more efficient to do a final table.concat than to concatenate all the way
	local output_tbl = {"table: "..name.."\n"}
	--indentation is a series of n x "\t" (tab characters), where n = order
	local indentation = string.rep("\t", order)
	--for all elements of the table
	for i,v in pairs(input_table) do
		--the start of the line is the indentation + table_indx
		table.insert(output_tbl, indentation..i.." = ")
		--if the value is a string or number, just concatenate
		if type(v) == "string" or type(v) == "number" then
			table.insert(output_tbl, v.."\n")
		--if it's a boolean, concatenate "true" or "false" according to the case
		elseif type(v) == "boolean" then
			if v then
				table.insert(output_tbl, "true\n")
			else
				table.insert(output_tbl, "false\n")
			end
		--if it's a table, repeat table2str a level deeper
		elseif type(v) == "table" then
			table.insert(output_tbl, "table:\n")
			table.insert(output_tbl, table2str("", order+1, v))
		--if v is nil, concatenate "nil"
		elseif not v then
			table.insert(output_tbl, "nil\n")
		--if v is something else, print type(v) e.g. functions
		else
			table.insert(output_tbl, "type: "..type(v).."\n")
		end
	end
	--returns the concatenation of all lines
	return table.concat(output_tbl)
end

--if we are just printing in screen
if _LOGMODE == "print" then
	logprint = print
	last_logprint = print
--if we print to a file
elseif _LOGMODE == "file" then
	logprint = function(message)
		local logfile1 = io.open(_LOGFILE,"a")
		logfile1:write(message.."\n")
		logfile1:close()
	end
	last_logprint = logprint
--if we want to print to a file efficiently
elseif _LOGMODE == "file_efficient" then
	--logprint adds an entry to the logging table
	logprint = function(message)
		table.insert(log_tbl, message.."\n")
	end
	--last_logprint writes the table.concat of all the log lines in a file and cleans the logging table
	last_logprint = function(message)
		local logfile1 = io.open(_LOGFILE,"a")
		table.insert(log_tbl, message.."\n")
		logfile1:write(table.concat(log_tbl))
		logfile1:close()
		log_tbl = {}
	end
else
	--empty functions
	logprint = function(message) end
	last_logprint = function(message) end
end

function send_command(command_name, url, key, type_of_transaction, value)
	--logs entrance in the function
	logprint("send_"..command_name..": START")
	logprint("send_"..command_name..": url=",url,"key=",key,"type_of_transaction=",type_of_transaction,"value=",value)
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
		logprint("send_"..command_name..": Error! \""..response_status.."\"")
		last_logprint("send_"..command_name..": END")
		--returns false and the error
		return false, response_status
	end

	--if it arrives here, it means it didn't enter inside the if
	logprint("send_"..command_name..": 200 OK received")
	--logs exit of the function
	last_logprint("send_"..command_name..": END")
	--if there is a response_body
	if type(response_body) == "table" and response_body[1] then
		--returns true (indicates a succesful call), and the return value
		return true, serializer.decode(response_body[1])
	end
	--if there was no response body, returns only "true"
	return true
end

function url2node(url)
	local separator = url:find(":")
	local ip = url:sub(1, separator-1)
	local port = url:sub(separator+1)
	return {ip=ip, port=port}
end

--function send_get
function send_get(url, key, type_of_transaction)

	logprint("send_get: START")

	--local get_ok, answer = send_command("GET", url, key, type_of_transaction)
	local get_ok, answer = rpcq.call(url2node(url), {"handle_get", key, type_of_transaction})
	
	local chosen_value = nil

	if not get_ok then
		return false
	end

	if (not answer) or (not answer[1]) then
		return true, nil
	end

	if type(answer[1].value) == "string" then
		chosen_value = ""
		logprint("send_get: value is string")
	elseif type(answer[1].value) == "number" then
		chosen_value = 0
	elseif type(answer[1].value) == "table" then
		logprint("send_get: value is a table")
	end

	--for evtl_consistent get
	local max_vc = {}
	for i2,v2 in ipairs(answer) do
		logprint("send_get: value is "..v2.value)
		logprint("send_get: chosen value is "..chosen_value)
		if type(v2.value) == "string" then
			if string.len(v2.value) > string.len(chosen_value) then --in this case is the max length, but it could be other criteria
				logprint("send_get: replacing value")
				chosen_value = v2.value
			end
		elseif type(v2.value) == "number" then
			if v2.value > chosen_value then --in this case is the max, but it could be other criteria
				logprint("send_get: replacing value")
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

	logprint("send_get: key: "..key..", value: "..chosen_value..", merged vector_clock:")
	logprint(table2str("max_vc", 0, max_vc))
	last_logprint("send_get: END")
	return true, chosen_value, max_vc
end

--function send_put
function send_put(url, key, type_of_transaction, value)
	logprint("send_put: START")
	--return send_command("PUT", url, key, type_of_transaction, value)
	return rpcq.call(url2node(url), {"handle_put", key, type_of_transaction, value)
end

function send_delete(url, key, type_of_transaction)
	logprint("send_delete: START")
	return rpcq.call(url2node(url), {"handle_delete", key, type_of_transaction})
end

function send_get_node_list(url)
	logprint("send_get_node_list: START")
	local send_ok, node_list = rpcq.call(url2node(url), {"handle_get_node_list"})
	logprint("send_get_node_list:")
	logprint(table2str("node_list", 0, node_list))
	last_logprint("send_get_node_list: END")
	return send_ok, node_list
end

function send_get_key_list(url)
	logprint("send_get_key_list: START")
	local send_ok, key_list = rpcq.call(url2node(url), {"handle_get_key_list"})
	logprint("send_get_key_list:")
	logprint(table2str("key_list", 0, key_list))
	last_logprint("send_get_key_list: END")
	return send_ok, key_list
end

function send_get_master(url, key)
	logprint("send_get_master: START")
	return rpcq.call(url2node(url), {"handle_get_master", key})
end

function send_get_all_records(url)
	logprint("send_get_all_records: START")
	return rpcq.call(url2node(url), {"handle_get_all_records"})
end

function send_change_log_lvl(url, log_level)
	logprint("send_change_log_lvl: START")
	return rpcq.call(url2node(url), {"handle_change_log_level", log_level})
end