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
-- END LIBRARIES

_LOGMODE = "print"
_LOGFILE = "/home/unine/Desktop/logfusesplay/log.txt"
local log_tbl = {}

socket.BLOCKSIZE = 10000000

-- FUNCTIONS

local function table2str(name, order, input_table)
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
elseif _LOGMODE == "file" then
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

	logprint("send_"..command_name..": START")

	local response_body = {}

	local request_source = ltn12.source.string(tostring(value))

	--AQUI ME QUEDE
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..(key or ""),
		method = command_name,
		headers = {

		},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_"..command_name..": Error "..response_status)
		last_logprint("send_"..command_name..": END")
		return false, response_status
	end

	logprint("send_"..command_name..": 200 OK received")
	last_logprint("send_"..command_name..": END")
	return true, serializer.decode(response_body[1])
end

--function send_put
function send_put_command(url, type_of_transaction, key, value)

	logprint("send_put: START")
	
	local response_body = nil
	
	local request_source = ltn12.source.string(tostring(value))

	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..key,
		method = "PUT",
		headers = {
			["Type"] = type_of_transaction,
			["Content-Length"] = string.len(value_str),
			["Content-Type"] =  "plain/text"
			},
		source = 
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_put: Error "..response_status)
		last_logprint("send_put: END")
		return false
	end

	logprint("send_put: PUT done.")
	last_logprint("send_put: END")
	return true
end

function send_get(url, type_of_transaction, key)

	logprint("send_get: START")

	local response_body = {}
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..key,
		method = "GET",
		headers = {
			["Type"] = type_of_transaction
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_get: Error "..response_status)
		last_logprint("send_get: END")
		return false
	end

	logprint("send_get: 200 OK received")
	logprint("send_get: Content of kv-store: "..key.." is:\n"..response_body[1].."\n")

	local answer = serializer.decode(response_body[1])

	logprint("send_get: answer decoded:")
	logprint(table2str("answer", 0, answer))

	if not answer[1] then
		logprint("send_get: No answer")
		last_logprint("send_get: END")
		return true, nil
	end

	local chosen_value = nil

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

function send_delete(url, type_of_transaction, key)

	logprint("send_delete: START\n")

	local response_body = {}
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..key,
		method = "DELETE",
		headers = {
			["Type"] = type_of_transaction
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_delete: Error "..response_status)
		last_logprint("send_delete: END")
		return false
	end

	logprint("send_delete: DELETE done.")
	last_logprint("send_delete: END")
	return true
end

function send_get_node_list(url)

	logprint("send_get_node_list: START\n")

	local response_body = {}
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/",
		method = "GET_NODE_LIST",
		headers = {},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_get_node_list: Error "..response_status)
		last_logprint("send_get_node_list: END")
		return false
	end

	logprint("send_get_node_list: 200 OK received")
	local response_tbl1 = serializer.decode(response_body[1])
	logprint("send_get_node_list: node list:")
	logprint(table2str("node_list", 0, response_tbl1))
	last_logprint("send_get_node_list: END")
	return true, response_tbl1
	end

end

function send_get_master(url, key)

	logprint("send_get_master: START")

	local response_body = {}
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/"..key,
		method = "GET_MASTER",
		headers = {
		},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_get_master: Error "..response_status)
		last_logprint("send_get_master: END")
		return false
	end

	logprint("send_get_master: 200 OK received")
	local response_tbl1 = serializer.decode(response_body[1])
	logprint(table2str("master", 0, response_tbl1))
	last_logprint("send_get_master: END")
	return true, response_tbl1
end

function send_get_all_records(url)

	logprint("send_get_all_records: START")

	local response_body = {}
	
	local response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..url.."/",
		method = "GET_ALL_RECORDS",
		headers = {},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status ~= 200 then
		logprint("send_get_all_records: Error "..response_status)
		last_logprint("send_get_all_records: END")
		return false
	end

	logprint("send_get_all_records: 200 OK received")
	local response_tbl1 = serializer.decode(response_body[1])
	logprint(table2str("records", 0, response_tbl1))
	last_logprint("send_get_all_records: END")
	return true, response_tbl1
end