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
local serializer = require"splay.lbinenc"
events = require"splay.events"

local neighborhood = nil

AS_LIB = false

-- END LIBRARIES

socket.BLOCKSIZE = 10000000

-- FUNCTIONS

function copy_tablez(input_table)
    local output_table = {}
    for i,v in pairs(input_table) do
        if type(v) == "table" then
            output_table[i] = copy_tablez(v)
        else
            output_table[i] = v
        end
    end
    return output_table
end

function print_tablez(name, order, input_table)
    local output_string = ""
    local indentation = ""
    for i=1,order do
        indentation = indentation.."\t"
    end
    for i,v in pairs(input_table) do
        if type(v) == "string" or type(v) == "number" then
            output_string = output_string..indentation..name.."."..i.." = "..v.."\n"
        elseif type(v) == "boolean" then
            if v == true then
                output_string = output_string..indentation..name.."."..i.." = true\n"
            else
                output_string = output_string..indentation..name.."."..i.." = false\n"
            end
        elseif type(v) == "table" then
            output_string = output_string..indentation..name.."."..i.." type table:\n"
            output_string = output_string..print_tablez(i, order+1, v)
        elseif not v then
        	output_string = output_string..indentation..name.."."..i.." is nil\n"
        else
            output_string = output_string..indentation..name.."."..i.." type "..type(v).."\n"
        end
    end
    return output_string
end

function send_put(ip_addr, port, type_of_transaction, key, value)
	
	--local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

    --logfile1:write("send_put: started\n")
    

	local response_body = nil
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	local value_str = ""..value

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/"..key,
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
		--print("PUT done.")
		--logfile1:write("send_put: PUT done.\n")
		--logfile1:close()
		return true
	else
		--print("Error "..response_status)
		--logfile1:write("send_put: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

end

function send_get(ip_addr, port, type_of_transaction, key)

	--local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

	--logfile1:write("send_get: started\n")

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/"..key,
		method = "GET",
		headers = {
			["Type"] = type_of_transaction
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		--print("Content of kv-store: "..key.." is:\n"..response_body[1])
		--logfile1:write("send_get: 200 OK received\n")
		----logfile1:write("Content of kv-store: "..key.." is:\n"..response_body[1].."\n")
	else
		print("Error "..response_status..":\n", response_body[1])
		----logfile1:write("send_get: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

	local answer = serializer.decode(response_body[1])

	local answer_string = print_tablez("answer", 0, answer)
	--print("send_get: answer decoded: \n"..answer_string)
	--logfile1:write("send_get: answer decoded: \n"..answer_string)

	if not answer[1] then
		--logfile1:write("send_get: No answer\n")
		--logfile1:close()
		return true, nil
	end

	local chosen_value = nil

	if type(answer[1].value) == "string" then
		chosen_value = ""
		----logfile1:write("send_get: value is string\n")
	elseif type(answer[1].value) == "number" then
		chosen_value = 0
	elseif type(answer[1].value) == "table" then
		----logfile1:write("send_get: value is a table\n")
	end
	local max_vc = {}
	for i2,v2 in ipairs(answer) do
		----logfile1:write("send_get: value is "..v2.value.."\n")
		----logfile1:write("send_get: chosen value is "..chosen_value.."\n")
		if type(v2.value) == "string" then
			if string.len(v2.value) > string.len(chosen_value) then --in this case is the max, but it could be other criteria
				----logfile1:write("send_get: replacing value\n")
				chosen_value = v2.value
			end
		elseif type(v2.value) == "number" then
			if v2.value > chosen_value then --in this case is the max, but it could be other criteria
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

	if not AS_LIB then
		print("key: "..key..", value: "..chosen_value..", merged vector_clock:")
		----logfile1:write("send_get: key: "..key..", value: "..chosen_value.."\n")
		for i2,v2 in pairs(max_vc) do
			print("", i2, v2)
		end
	end

	--logfile1:close()

	return true, chosen_value, max_vc
end

function send_delete(ip_addr, port, type_of_transaction, key)

	local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

	--logfile1:write("send_delete: started\n")

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/"..key,
		method = "DELETE",
		headers = {
			["Type"] = type_of_transaction
			},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		--print("PUT done.")
		--logfile1:write("send_delete: DELETE done.\n")
		--logfile1:close()
		return true
	else
		--print("Error "..response_status)
		--logfile1:write("send_delete: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

end

function send_get_node_list(ip_addr, port)

	--local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

	--logfile1:write("send_delete: started\n")

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/",
		method = "GET_NODE_LIST",
		headers = {},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		print("GET_NODE_LIST command sent.")
		--logfile1:write("send_delete: DELETE done.\n")
		--logfile1:close()
		local response_tbl1 = serializer.decode(response_body[1])
		if type(response_tbl1) == "table" then
			print("neighborhood size=", #response_tbl1)
			--print(print_tablez("neighborhood", 0, response_tbl1))
		end
		return true, response_tbl1
	else
		--print("Error "..response_status)
		--logfile1:write("send_delete: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

end

function send_get_master(ip_addr, port, key)

	--local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

	--logfile1:write("send_delete: started\n")

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/"..key,
		method = "GET_MASTER",
		headers = {
			["Type"] = "consistent"
		},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	if response_status == 200 then
		print("GET_MASTER command sent.")
		--logfile1:write("send_delete: DELETE done.\n")
		--logfile1:close()
		local response_tbl1 = serializer.decode(response_body[1])
		if type(response_tbl1) == "table" then
			--print("neighborhood size=", #response_tbl1)
			print(print_tablez("master", 0, response_tbl1))
		end
		return true, response_tbl1
	else
		--print("Error "..response_status)
		--logfile1:write("send_delete: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

end

function send_get_all_records(ip_addr, port)

	--local logfile1 = io.open("/home/unine/Desktop/logfusesplay/log.txt","a")

	--logfile1:write("send_delete: started\n")

	local response_body = {}
	local response_to_discard = nil
	local response_status = nil
	local response_headers = nil
	local response_status_line = nil

	response_to_discard, response_status, response_headers, response_status_line = http.request({
		url = "http://"..ip_addr..":"..port.."/",
		method = "GET_ALL_RECORDS",
		headers = {},
		source = ltn12.source.empty(),
		sink = ltn12.sink.table(response_body)
	})

	--print(ip_addr, port, response_status)

	if response_status == 200 then
		--print("GET_ALL_RECORDS command sent.")
		--logfile1:write("send_delete: DELETE done.\n")
		--logfile1:close()
		local response_tbl1 = serializer.decode(response_body[1])
		if type(response_tbl1) == "table" then
			--print("records size=", #response_tbl1)
			--print(print_tablez("DB", 0, response_tbl1))
		end
		return true, response_tbl1
	else
		--print("Error "..response_status)
		--logfile1:write("send_delete: Error "..response_status.."\n")
		--logfile1:close()
		return false
	end

end

if not AS_LIB then

	events.run(function()
		dofile("ports.lua")
		math.randomseed(os.time())
		local key = crypto.evp.digest("sha1",math.random(100000))

		local ip_addr = arg[1]
		local port = tonumber(arg[2])

		local get_node_list_ok = nil

		get_node_list_ok, neighborhood = send_get_node_list(ip_addr, port)
		print(print_tablez("node", 0, neighborhood))
		--if not get_node_list_ok then os.error("ERROR IN GET NODE LIST") end
		print("Key="..key)
		send_get_master(ip_addr, port, key)


		if #neighborhood < 200 then
			print("So far only "..#neighborhood.." nodes")
		end

		local consistency_model = "consistent"
--[[
TODOS EN ESPAÑOL:

IMPRIMIR LA ID
SOLO EL I DE LA TABLA
HACER UN CHECKER AUTOMATICO
PROBAR CON MAS NODOS
HACER EL JOIN

--]]
	for j=1,3 do
		key = crypto.evp.digest("sha1",math.random(100000))
		for i=1, 3 do
			local node = misc.random_pick(neighborhood)
			print("Key is "..key)
	--		send_put(port, "evtl_consistent", key, i*10)
	--		send_put(port, "consistent", key, i*10)
			send_put(node.ip, node.port+1, consistency_model, key, i*10)
			events.sleep(0.5)
		end

		for i=1, 1 do
			local node = misc.random_pick(neighborhood)
	--		send_get(port, "evtl_consistent", key)
	--		send_get(port, "consistent", key)
			send_get(node.ip, node.port+1, consistency_model, key)
			events.sleep(0.5)
		end
	end
	--]]
		local success1 = 0
		for i,v in pairs(neighborhood) do
			local ok, node_db = send_get_all_records(v.ip, v.port+1)
			if ok then
				if type(node_db) == "table" then
					local node_db_empty = true
					for i2,v2 in pairs(node_db) do
						node_db_empty = false
						node_db[i2] = serializer.decode(v2)
					end
					if not node_db_empty then
						print(print_tablez(v.ip..":"..v.port..".DB", 0, node_db))
					end
				end
			success1 = success1 + 1
			end
			events.sleep(0.3)
		end
		print("total successful = "..success1)
	end)
end
