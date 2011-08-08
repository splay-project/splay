--[[
       Splay ### v1.0.1 ###
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

local table = require"table"
local math = require"math"
local string = require"string"
-- for hashing
local crypto	= require"crypto"
-- for RPC calls
local rpc	= require"splay.rpc"
-- for the HTTP server
local net	= require"splay.net"
-- for enconding/decoding the bucket
local enc	= require"splay.benc"
-- for handling hexa strings
local misc	= require"splay.misc" --TODO look if the use of splay.misc fits here
-- for handling threads
local events	= require"splay.events" --TODO look if the use of splay.events fits here
-- for encoding/decoding the GET answer
local json	= require"json" --TODO look if the use of json fits here


--TODO CHECK which ones are going to be used
local assert = assert
local error = error
local ipairs = ipairs
local loadstring = loadstring
local next = next
local pairs = pairs
local pcall = pcall
local print = print
local setmetatable = setmetatable
local type = type
local tonumber = tonumber
local tostring = tostring
local unpack = unpack
local log = log

local base = _G

module("splay.distdb")

_COPYRIGHT   = "Copyright 2011 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Distributed DB functions."
_VERSION     = "0.99.0"

local db_table = {}
local locked_keys = {}
local n_replicas = 0 --TODO maybe this should match with settings
local min_replicas_write = 0 --TODO maybe this should match with settings
local min_replicas_read = 0 --TODO maybe this should match with settings
local some_timeout = 15
local neighborhood = {}
local next_node = nil
local last_node = nil
local ping_thread = nil

local init_done = false

--function print_node: prints the IP address, port, and ID of a given node
local function get_position()
	for i=1,#neighborhood do
		if neighborhood[i].id == n.id then
			return i
		end
	end
end



--=========== FROM DIST-DB.LUA BEGINNING
--function calculate_id: calculates the node ID from ID and port
local function calculate_id(node)
	return crypto.evp.digest("sha1",node.ip..node.port)
end

--function get_master: looks for the master of a given ID
local function get_master(id)
	--the master is initialized as equal to the last node
	local masters_pos = #neighborhood
	local master = neighborhood[masters_pos]
	--for all the neighbors but the first one
	for i=1,#neighborhood-1 do
		--compares the id with the id of the node
		local compare = misc.bighex_compare(neighborhood[i].id, id)
		--if id is bigger
		if (compare == 1) then
			--if i is not 1
			if i > 1 then
				masters_pos = i-1
				--the master is node i-1
				master = neighborhood[masters_pos]
			end
			--get out of the loop
			break
		end
	end
	--prints the master ID
	--log:print("master --> "..master.id)
	--returns the master
	return master, masters_pos
end

--function get_responsibles: looks for the nodes that are responsible of a given ID
local function get_responsibles(id)

	local master, masters_pos = get_master(id)

	local responsibles = {master}

	local n_responsibles = n_replicas

	if n_replicas > #neighborhood then
		n_responsibles = #neighborhood
	end

	for i=1,n_responsibles - 1 do
		if masters_pos + i <= #neighborhood then
			table.insert(responsibles, neighborhood[masters_pos + i])
		else
			table.insert(responsibles, neighborhood[masters_pos + i - #neighborhood])
		end
	end
	return responsibles, masters_pos
end

--function print_me: prints the IP address, port, and ID of the node
local function print_me()
	log:print("ME",n.ip, n.port, n.id, n.position)
end

--function print_node: prints the IP address, port, and ID of a given node
local function print_node(node)
	log:print(node.ip, node.port, node.id)
end

function print_all()
	print_me()
	log:print()
	local for_ports_lua = "for ports.lua "
	for _,v in ipairs(neighborhood) do
		print_node(v)
		for_ports_lua = for_ports_lua..", "..(v.port+1)
	end
	log:print(n.port..": "..for_ports_lua)

end

local function neighbor_position(node)
	for i,v in ipairs(neighborhood) do
		if node.id == v.id then
			return i
		end
	end
	return false
end

function add_node_to_neighborhood(node)
	table.insert(neighborhood, node)
	table.sort(neighborhood, function(a,b) return a.id<b.id end)
	n.position = get_position()
	if n.position == 1 then
		next_node = neighborhood[2]
		last_node = neighborhood[#neighborhood]
	elseif n.position == #neighborhood then
		next_node = neighborhood[1]
		last_node = neighborhood[#neighborhood - 1]
	else
		next_node = neighborhood[n.position + 1]
		last_node = neighborhood[n.position - 1]
	end
	log:print(n.port..": adding node "..node.id.." to my list")

end

function remove_node_from_neighborhood(node_pos)
	local node = neighborhood[node_pos]
	table.remove(neighborhood, node_pos)
	n.position = get_position()
	if #neighborhood == 1 then
		next_node = nil
		last_node = nil
	elseif n.position == 1 then
		next_node = neighborhood[2]
		last_node = neighborhood[#neighborhood]
	elseif n.position == #neighborhood then
		next_node = neighborhood[1]
		last_node = neighborhood[#neighborhood - 1]
	else
		next_node = neighborhood[n.position + 1]
		last_node = neighborhood[n.position - 1]
	end
	log:print(n.port..": removing node "..node.id.." of my list")
end

function receive_gossip(message, neighbor_about)
--TODO this gossiping technique may not work for 2 failures in 1 period
	if message == "add" then
		if neighbor_position(neighbor_about) then
			return nil
		end
		add_node_to_neighborhood(neighbor_about)
	elseif message == "remove" then
		local neighbor_about_pos = neighbor_position(neighbor_about)
		if not neighbor_about_pos then
			return nil
		end
		remove_node_from_neighborhood(neighbor_about_pos)
	end

	events.sleep(math.random(100)/20)

	events.thread(function()
		log:print(n.port..": gossiping to "..last_node.id..", message: "..message..", about: "..neighbor_about.id)
		rpc.call(last_node, {"distdb.receive_gossip", message, neighbor_about})
	end)

end

local function gossip_changes(message, neighbor_about)

	events.thread(function()
		log:print(n.port..": gossiping to "..last_node.id..", message: "..message..", about: "..neighbor_about.id)
		rpc.call(last_node, {"distdb.receive_gossip", message, neighbor_about})
	end)
end

local function ping_others()
	if next_node then
		log:print(n.port..": pinging "..next_node.id)
		local ok = rpc.ping(next_node)
		if not ok then
			log:print(n.port..": i lost neighbor "..next_node.id)
			local node_about = {id = next_node.id}
			remove_node_from_neighborhood(next_node)
			gossip_changes("remove", node_about)
		end
	end
end

function add_me(node_to_add)
	if neighbor_position(node_to_add) then
		return nil
	end
	add_node_to_neighborhood(node_to_add)
	gossip_changes("add", node_to_add)
	return neighborhood
end

--function parse_http_request: parses the payload of the HTTP request
function parse_http_request(socket)
	--print("\n\nHEADER\n\n")
	local first_line = socket:receive("*l")
	local first_line_analyzer = {}
	for piece in string.gmatch(first_line, "[^ ]+") do
		table.insert(first_line_analyzer, piece)
	end
	local method = first_line_analyzer[1]
	local resource = first_line_analyzer[2]
	local http_version = first_line_analyzer[3]
	local headers = {}
	while true do
		local data = socket:receive("*l")
		if ( #data < 1 ) then
			break
		end
		--print("data = "..data)
		local header_separator = string.find(data, ":")
		local header_k = string.sub(data, 1, header_separator-1)
		local header_v = string.sub(data, header_separator+2)
		--print(header_k, header_v)
		headers[header_k] = header_v
	end

	--local body = socket:receive(1) -- Receive 1 byte from the socket's buffer
	--print("\n\nBODY\n\n")
	-- initializes the request body read from client as empty string
	local bytes_left = tonumber(headers["content-length"] or headers["Content-Length"])
	local body = nil
	if bytes_left then
		--print("body length = "..bytes_left)
		body = socket:receive(bytes_left)
		--print("body = "..body)
	end

	return method, resource, http_version, headers, body
end

--REQUEST HANDLING FUNCTIONS

--function handle_get_bucket: handles a GET BUCKET request as the Coordinator of the Access Key ID
function handle_get(type_of_transaction, key)
	log:print(n.port.." handling a GET for key: "..key)
	local responsibles = get_responsibles(key)
	local chosen_node_id = math.random(#responsibles)
	--log:print(n.port..": choosing responsible n. "..chosen_node_id)
	local chosen_node = responsibles[chosen_node_id]
	local function_to_call = nil
	if type_of_transaction == "consistent" then
		function_to_call = "distdb.consistent_get"
	else
		function_to_call = "distdb.evtl_consistent_get"
	end
	local ok, answer = rpc.call(chosen_node, {function_to_call, key, value})
	return ok, answer
end

--function handle_put_bucket: handles a PUT BUCKET request as the Coordinator of the Access Key ID
function handle_put(type_of_transaction, key, value) --TODO check about setting N,R,W on the transaction
	log:print(n.port..": handling a PUT for key: "..key..", value: "..value)
	local responsibles = get_responsibles(key)
	local chosen_node_id = math.random(#responsibles)
	--log:print(n.port..": choosing responsible n. "..chosen_node_id)
	local chosen_node = responsibles[chosen_node_id]
	--log:print(n.port..": Chosen node is "..chosen_node.id)
	--[[TESTING WRONG NODE
	if math.random(5) == 1 then
		local new_node_id = math.random(#job.nodes)
		chosen_node = job.nodes[new_node_id]
		log:print(n.port..": Chosen node changed")
	end
	]]--
	--log:print()
	local function_to_call = nil
	if type_of_transaction == "consistent" then
		function_to_call = "distdb.consistent_put"
	else
		function_to_call = "distdb.evtl_consistent_put"
	end
	local answer = rpc.call(chosen_node, {function_to_call, key, value})
	return answer
end


--TABLE OF FORWARDING FUNCTIONS

local forward_request = {
	["GET"] = handle_get,
	["PUT"] = handle_put,
	}


--FRONT-END FUNCTIONS

--function handle_http_message: handles the incoming messages (HTTP requests)
function handle_http_message(socket)
	local client_ip, client_port = socket:getpeername()
	local method, resource, http_version, headers, body = parse_http_request(socket)
	local key = string.sub(resource, 2)
	log:print(n.port..": resource is "..resource)
	log:print(n.port..": requesting for "..key)

	local value = body
	local type_of_transaction = headers["Type"] or headers["type"]
	log:print(n.port..": http request parsed, a "..method.." request will be forwarded")
	log:print(n.port..": key: "..key..", value:", value)
	local ok, answer = forward_request[method](type_of_transaction, key, tonumber(value))

	local http_response_body = nil
	local http_response_code = nil
	local http_response_content_type = nil
	log:print(n.port..": answer is a "..type(answer))
	if ok then
		if answer then
			http_response_body = json.encode(answer)
		end
		http_response_code = "200 OK"
		http_response_content_type = "text/plain"

	else
		http_response_code = "409 Conflict"
	end

	local http_response = "HTTP/1.1 "..http_response_code.."\r\n"
	if http_response_body then
		http_response = http_response..
			"Content-Length: "..#http_response_body.."\r\n"..
			"Content-Type: "..http_response_content_type.."\r\n\r\n"..http_response_body
	else
		http_response = http_response.."\r\n"
	end

	socket:send(http_response)
-- 	if string.sub(header,1,8) == "OPTIONS" then
-- 		return handle_options_method(socket)
-- 	else
-- 		handle_post_method(socket,jsonmsg)
-- 	end
end


--=========== FROM DIST-DB.LUA END

function init(job)
	if not init_done then
		init_done = true
		--TODO add node to the db network
		--TODO start pinging processes
		--TODO the rest of init
		--takes IP address and port from job.me
		n = {ip=job.me.ip, port=job.me.port}
		--initializes the randomseed with the port
		math.randomseed(n.port)
		--calculates the ID by hashing the IP address and port
		n.id = calculate_id(job.me)


		--server listens through the rpc port + 1
		local http_server_port = n.port+1
		--puts the server on listen
		net.server(http_server_port, handle_http_message)

		--initializes db_table
		db_table = {}
		--initializes the variable holding the number of replicas
		n_replicas = 10 --TODO this should be configurable
		min_replicas_write = 3 --TODO this should be configurable
		min_replicas_read = 3 --TODO this should be configurable

		--starts the RPC server for internal communication
		rpc.server(n.port)


		--initializes the neighborhood as an empty table
		if job.position == 1 then
			neighborhood = {n}
		else
			neighborhood = rpc.call(job.nodes[1], {"distdb.add_me", n})
		end

		n.position = get_position()



		--PRINTING STUFF
		--prints a initialization message
		log:print(n.port..": HTTP server - Started on port "..http_server_port)

		print_all()

		ping_thread = events.periodic(5, ping_others)
	end
end

function stop()
	net.stop_server(n.port+1)
	rpc.stop_server(n.port)
end

function consistent_put(key, value)
	local master = get_master(key) --TODO maybe optimize this by changing to master, masters_pos
	if master.id ~= n.id then
		return false, "wrong master"
	end
	local master_id = n.position
	local answers = 0
	local successful = false
	if not locked_keys[key] then --TODO change this for a queue system
		locked_keys[key] = true
		events.thread(function()
			local ok = put_local(key, value)
			if ok then
				answers = answers + 1
				if answers >= n_replicas then --TODO adapt this to n_responsibles
					events.fire(key)
				end
			end

		end)
		for i = 1, n_replicas - 1 do
			events.thread(function()
				local replica_id = nil
				if master_id + i <= #neighborhood then
					replica_id = master_id + i
				else
					replica_id = master_id + i - #neighborhood
				end
				--log:print("i: "..i)
				--log:print("replica id: "..replica_id)
				local ok = rpc.call(neighborhood[replica_id], {"distdb.put_local", key, value})
				if ok then
					answers = answers + 1
					if answers >= n_replicas then
						events.fire(key)
					end
				end
			end)
		end
		successful = events.wait(key, some_timeout) --TODO match this with settings --TODO 2 watch out with node failures, how to handle???
		locked_keys[key] = nil
	end
	return successful
end

function evtl_consistent_put(key, value)
	local not_responsible = true
	local responsibles = get_responsibles(key)
	for i,v in ipairs(responsibles) do
		if v.id == n.id then
			not_responsible = false
		end
	end
	if not_responsible then
		return false, "wrong node"
	end
	local answers = 0
	local successful = false

	--TODO consider min replicas and neighborhood

	if not locked_keys[key] then --TODO change this for a queue system
		locked_keys[key] = true
		events.thread(function()
			local ok = put_local(key, value, n)
			if ok then
				answers = answers + 1
				if answers >= min_replicas_write then
					events.fire(key)
				end
			end
		end)
		for i,v in ipairs(responsibles) do
			if v.id ~= n.id then
				events.thread(function()
					local ok = rpc.call(v, {"distdb.put_local", key, value, n})
					if ok then
						answers = answers + 1
						if answers >= min_replicas_write then
							events.fire(key)
						end
					end
				end)
			end
		end
		successful = events.wait(key, some_timeout) --TODO match this with settings
		locked_keys[key] = nil
	end
	return successful
end

function consistent_get(key)
	local not_responsible = true
	local responsibles = get_responsibles(key)
	for i,v in ipairs(responsibles) do
		if v.id == n.id then
			not_responsible = false
		end
	end
	if not_responsible then
		return false, "wrong node"
	end
	return true, get_local(key) --TODO maybe it is better to enclose this on a table to make it output-compatible with eventually-consistent get
end

function evtl_consistent_get(key)
	local not_responsible = true
	local responsibles = get_responsibles(key)
	for i,v in ipairs(responsibles) do
		if v.id == n.id then
			not_responsible = false
		end
	end
	if not_responsible then
		return false, "wrong node"
	end
	local answers = 0
	local answer_data = {}
	local return_data = {}
	local latest_vector_clock = {}
	local successful = false
	for i,v in ipairs(responsibles) do
		events.thread(function()
			if v.id == n.id then
				answer_data[v.id] = get_local(key) --TODO deal with attemps of writing a previous version
			else
				answer_data[v.id] = rpc.call(v, {"distdb.get_local", key})
			end
			if answer_data[v.id] then
				log:print(n.port..": received from "..v.id.." key: "..key..", value: "..answer_data[v.id].value..", enabled: ", answer_data[v.id].enabled, "vector_clock:")
				for i2,v2 in pairs(answer_data[v.id].vector_clock) do
					log:print(n.port..":",i2,v2)
				end
				answers = answers + 1
				if answers >= min_replicas_read then
					events.fire(key)
				end
			end
		end)
	end
	successful = events.wait(key, some_timeout) --TODO match this with settings
	if not successful then
		return false, "timeout"
	end
	local comparison_table = {}
	for i,v in pairs(answer_data) do
		comparison_table[i] = {}
		for i2,v2 in pairs(answer_data) do
			comparison_table[i][i2] = 0
			if i2 ~= i then
				--log:print("comparing "..i.." and "..i2)
				local do_comparison = false
				if not comparison_table[i2] then
					do_comparison = true
				elseif not comparison_table[i2][i] then
					do_comparison = true
				end
				if do_comparison then
					local merged_vector = {}
					--log:print("first "..i)
					for i3,v3 in pairs(v.vector_clock) do
						merged_vector[i3] = {value=v3, max=1}
						--log:print(i3, v3)
					end
					--log:print("then "..i2)
					for i4,v4 in pairs(v2.vector_clock) do
						--log:print(i4, v4)
						if merged_vector[i4] then
							if v4 > merged_vector[i4].value then
								merged_vector[i4] = {value=v4, max=2}
							elseif v4 == merged_vector[i4].value then
								merged_vector[i4].max = 0
							end
						else
							merged_vector[i4] = {value=v4, max=1}
						end
					end
					for i5,v5 in pairs(merged_vector) do
						--log:print(i5, v5.value, v5.max)
						if v5.max == 1 then
							if comparison_table[i][i2] == 0 then
								comparison_table[i][i2] = 1
							elseif comparison_table[i][i2] == 2 then
								comparison_table[i][i2] = 3
							end
						elseif v5.max == 2 then
							if comparison_table[i][i2] == 0 then
								comparison_table[i][i2] = 2
							elseif comparison_table[i][i2] == 1 then
								comparison_table[i][i2] = 3
							end
						end
					end
				end
				--log:print("comparison_table: "..comparison_table[i][i2])
			end
		end
	end
	for i,v in pairs(comparison_table) do
		for i2,v2 in pairs(v) do
			if v2 == 1 then
				answer_data[i2] = nil
				--log:print("deleting answer from "..i2.." because "..i.." is fresher")
			elseif v2 == 2 then
				answer_data[i] = nil
				--log:print("deleting answer from "..i.." because "..i2.." is fresher")
			end
		end
	end
	log:print(n.port..": remaining answers")
	for i,v in pairs(answer_data) do
		log:print(n.port..":", i, v.value)
		table.insert(return_data, v)
	end
	return true, return_data
end

--function put_local: writes a k,v pair. TODO should be atomic? is it?
function put_local(key, value, src_write)
	--TODO how to check if the source node is valid?
	--adding a random failure to simulate failed local transactions
	if math.random(5) == 1 then
		log:print(n.port..": NOT writing key: "..key)
		return false, "404"
	end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.port..": NOT writing key, wrong key type")
		return false, "wrong key type"
	end
	--if value is not a string or a number, dont accept the transaction
	if type(value) ~= "string" and type(value) ~= "number" then
		log:print(n.port..": NOT writing key, wrong value type")
		return false, "wrong value type"
	end

	if not src_write then
		src_write = {id="version"} --for compatibility with consistent_put
	end

	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not db_table[key] then
		db_table[key] = {value=value, enabled=true, vector_clock={}}
		db_table[key].vector_clock[src_write.id] = 1
	else
	--else, replace the value and increase the version
		db_table[key].value=value
		if db_table[key].vector_clock[src_write.id] then
			db_table[key].vector_clock[src_write.id] = db_table[key].vector_clock[src_write.id] + 1
		else
			db_table[key].vector_clock[src_write.id] = 1
		end
		--TODO handle enabled
		--TODO add timestamps
	end
	log:print(n.port..": writing key: "..key..", value: "..value..", enabled: ", db_table[key].enabled, "vector_clock:")
	for i,v in pairs(db_table[key].vector_clock) do
		log:print(n.port..":",i,v)
	end
	return true
end

function get_local(key)
	--adding a random failure to simulate failed local transactions
	if math.random(10) == 1 then
		return nil
	end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	return db_table[key]
end

