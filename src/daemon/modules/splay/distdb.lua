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

--REQUIRED LIBRARIES

local table = require"table"
local math = require"math"
local string = require"string"
-- for hashing
local crypto	= require"crypto"
-- for RPC calls
local rpc	= require"splay.rpc" --TODO think about urpc vs rpc
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


--REQUIRED FUNCTIONS AND OBJECTS

local assert = assert --could be used
local error = error --could be used
local ipairs = ipairs
local next = next
local pairs = pairs
local pcall = pcall
local type = type
local tonumber = tonumber
local tostring = tostring
local log = log
local base = _G


--naming the module
module("splay.distdb")

--authoring info
_COPYRIGHT   = "Copyright 2011 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Distributed DB functions."
_VERSION     = "0.99.0"


--LOCAL VARIABLES

--db_table holds all records that are locally handled by the node
local db_table = {}
--locked_keys contains all the keys that are being modified, thus are locked
local locked_keys = {}
--n_replicas is the number of nodes that store a k,v record
local n_replicas = 0 --TODO maybe this should match with some distdb settings object
--min_replicas_write is the minimum number of nodes that must write a k,v to be considered
--successful (only for eventually consistent put)
local min_replicas_write = 0 --TODO maybe this should match with some distdb settings object
--min_replicas_write is the minimum number of nodes that must read k,v to have
--quorum (only for eventually consistent get)
local min_replicas_read = 0 --TODO maybe this should match with some distdb settings object
--rpc_timeout is the time in seconds that a node waits for an answer from another node on any rpc call
local rpc_timeout = 15
--paxos_propose_timeout is the time in seconds that a Proposer waits that all Acceptors answer a Propose message
local paxos_propose_timeout = 15
--paxos_accept_timeout is the time in seconds that a Proposer waits that all Acceptors answer an Accept message
local paxos_accept_timeout = 15
--paxos_learn_timeout is the time in seconds that an Acceptor waits that all Learners answer a Learn message
local paxos_learn_timeout = 15
--neighborhood is a table containing tables that contains the ip address, port and ID of all other nodes
local neighborhood = {}
--next_node is a table containing the ip addr, port and ID of the smallest node with bigger ID (next on the ring)
local next_node = nil
--previous_node is a table containing the ip addr, port and ID of the biggest node with smaller ID (previous on the ring)
local previous_node = nil
--init_done is a flag to avoid double initialization
local init_done = false
--prop_ids holds the Proposal IDs for Paxos operations (used by Proposer)
local prop_ids = {}
--paxos_max_retries is the maximum number of times a Proposer can try a Proposal
local paxos_max_retries = 5 --TODO maybe this should match with some distdb settings object


--LOCAL FUNCTIONS

--function get_position returns the position of the node on the ring
local function get_position(node)
	--if no node is specified
	if not node then
		--checks the ID of the node itself
		node = {id = n.id}
	end
	--for all neighbors
	for i = 1, #neighborhood do
		--if ID is the same as node.id
		if neighborhood[i].id == node.id then
			--return the index
			return i
		end
	end
end

--function calculate_id: calculates the node ID from its ip address and port
local function calculate_id(node)
	--if no node is specified
	if not node then
		--calculates the ID from the ip addr and port of the node itself
		node = {ip = n.ip, port = n.port}
	end
	--returns a SHA1 hash of the concatenation of ip addr + port
	return crypto.evp.digest("sha1", node.ip..node.port)
end

--function get_next_node returns the node in the ring after the specified node
local function get_next_node(node)
	--if neighborhood is a list of only 1 node
	if #neighborhood == 1 then
		--return nil
		return nil
	end
	--gets the position with the function get_position; if no node is specified, get_position
	--will return the position of the node itself
	local node_pos = get_position(node)
	--if the node is the last on the neighborhood list
	if node_pos == #neighborhood then
		--return the first node and position=1
		return neighborhood[1], 1
	--else
	else
		--return the node whose position = node_pos + 1
		return neighborhood[node_pos + 1], (node_pos + 1)
	end
end

--function get_previous_node returns the node in the ring before the specified node
local function get_previous_node(node)
	--if neighborhood is a list of only 1 node
	if #neighborhood == 1 then
		--return nil
		return nil
	end
	--gets the position with the function get_position; if no node is specified, get_position
	--will return the position of the node itself
	local node_pos = get_position(node)
	--if the node is the first on the neighborhood list
	if node_pos == 1 then
		--return the last node
		return neighborhood[#neighborhood], #neighborhood
	--else
	else
		--return the node whose position = node_pos - 1
		return neighborhood[node_pos - 1], (node_pos - 1)
	end
end

--function get_master: looks for the master of a given key
local function get_master(key)
	--the master is initialized as equal to the last node
	local master_pos = 1
	local master = neighborhood[1]
	--if the neighborhood is only one node, this is the master
	if #neighborhood == 1 then
		return master, master_pos
	end
	--for all the neighbors but the first one
	for i = 2, #neighborhood do
		--compares the key with the id of the node
		local compare = misc.bighex_compare(neighborhood[i].id, key)
		--if node ID is bigger
		if (compare == 1) then
			master_pos = i
			--the master is node i
			master = neighborhood[i]
			--get out of the loop
			break
		end
	end
	--prints the master ID
	--log:print("master --> "..master.id)
	--returns the master
	return master, master_pos
end

--function get_responsibles: looks for the nodes that are responsible of a given key
local function get_responsibles(key)
	--gets the master of the key
	local master, master_pos = get_master(key)
	--the first responsible is the master
	local responsibles = {master}
	--the number of responsibles is in principle = number of replicas
	local n_responsibles = n_replicas
	--if the size of the neighborhood is less than that, n_responsibles = size of neighborhood
	if n_replicas > #neighborhood then
		n_responsibles = #neighborhood
	end
	--repeat n_responsibles - 1 times:
	for i = 1, (n_responsibles - 1) do
		--if master_pos + i is less or equal to the size of neighborhood
		if master_pos + i <= #neighborhood then
			--insert the node with this position
			table.insert(responsibles, neighborhood[master_pos + i])
		--else
		else
			--insert the node with position = master_pos + i - #neighborhood (closing the ring)
			table.insert(responsibles, neighborhood[master_pos + i - #neighborhood])
		end
	end
	--return the list of responsible nodes and the position of the master node
	return responsibles, master_pos
end

--function print_me: prints the IP address, port and position of the node
local function print_me()
	log:print(n.id..":print_me: ME! IP:port=", n.ip..":"..n.port, "position=", n.position)
end

--function print_node: prints the IP address, port, and ID of a given node
local function print_node(node)
	log:print(n.id..":print_node: neighbor=", node.ip, node.port, node.id)
end

--function print_all: prints the node itself and its neighbors
function print_all()
	print_me()
	log:print()
	--for the conf file "ports.lua" of the client test file
	local for_ports_lua = "for ports.lua "
	for _,v in ipairs(neighborhood) do
		print_node(v)
		for_ports_lua = for_ports_lua..", "..(v.port+1)
	end
	log:print(n.id..":print_all: "..for_ports_lua)

end

--function add_node_to_neighborhood: adds a node to the neighborhood table, re-sorts and updates n.position
function add_node_to_neighborhood(node)
	--if node is nil don't do anything
	if not node then
		return nil
	end
	--insert the node
	table.insert(neighborhood, node)
	--sort the neighborhood table
	table.sort(neighborhood, function(a,b) return a.id<b.id end)
	--updates the node's position
	n.position = get_position()
	--updates the "pointer" to the next node
	next_node = get_next_node()
	--updates the "pointer" to the previous node
	previous_node = get_previous_node()
	--logs
	log:print(n.id..":add_node_to_neighborhood: adding node="..node.id.." to my list")

end

--function remove_node_from_neighborhood: removes a node from the neighborhood table, re-sorts and updates n.position
function remove_node_from_neighborhood(node_pos)
	--TODO take care of n_nodes < n_replicas
	--gets the node from the table before removal
	local node = neighborhood[node_pos]
	--removes it from it
	table.remove(neighborhood, node_pos)
	--recalculates n.position
	n.position = get_position()
	--updates the "pointer" to the next node
	next_node = get_next_node()
	--updates the "pointer" to the previous node
	previous_node = get_previous_node()
	--logs
	log:print(n.id..":remove_node_from_neighborhood: removing node="..node.id.." of my list")
end

--function receive_gossip: updates the table if necessary and forwards the gossip
function receive_gossip(message, neighbor_about)
	--TODO this gossiping technique may not work for 2 failures in 1 whole gossiping period
	--if the message is an "add"
	if message == "add" then
		--if get_position returns something, it means the node is already in the list, so it returns
		if get_position(neighbor_about) then
			return nil
		end
		--if not, add the node to the neighborhood table
		add_node_to_neighborhood(neighbor_about)
	--if the message is a "remove"
	elseif message == "remove" then
		--gets the position from the arguments of the function
		local neighbor_about_pos = get_position(neighbor_about)
		--if the node does not exist, it returns
		if not neighbor_about_pos then
			return nil
		end
		--else, it removes it from the neighbordhood table
		remove_node_from_neighborhood(neighbor_about_pos)
	end
	--sleep for a random time between 0 and 2sec
	--events.sleep(math.random(100)/50)

	--forward the gossip to the previous node
	events.thread(function()
		log:print(n.id..":receive_gossip: gossiping to node="..previous_node.id..", message="..message..", about node="..neighbor_about.id)
		rpc.call(previous_node, {"distdb.receive_gossip", message, neighbor_about})
	end)

end

--function gossip_changes: starts a event-based gossip to announce a node adding or removal
local function gossip_changes(message, neighbor_about)
	if previous_node then
		--create the gossip to the previous node
		events.thread(function()
			log:print(n.id..":gossip_changes: gossiping to node="..previous_node.id..", message="..message..", about node="..neighbor_about.id)
			rpc.call(previous_node, {"distdb.receive_gossip", message, neighbor_about})
		end)
	end
end

--function ping_others: periodic function that pings the next node on the ring
local function ping_others()
	--if there is a next_node (it could be the case of a 1-node ring, where the node will not ping anyone)
	if next_node then
		--logs
		--log:print(n.id..": pinging "..next_node.id)
		--pings, and if the response is not ok
		if not rpc.ping(next_node) then --TODO should be after several tries
			--logs that it lost a neighbor
			log:print(n.id..":ping_others: i lost neighbor="..next_node.id)
			--creates an object node_about to insert it into the message to be gossipped
			local node_about = {id = next_node.id}
			--calculates the position of the next node
			local next_node_pos = get_position(next_node)
			--removes the node from its table
			remove_node_from_neighborhood(next_node_pos)
			--gossips the removal
			gossip_changes("remove", node_about)
		end
	end
end

--function add_me: called by a new node to the RDV node (job.nodes[1]) to retrieve the neighborhood table and make him gossip the adding
function add_me(node_to_add)
	--if the node is already in the ring, leave
	if get_position(node_to_add) then
		return nil
	end
	--add the node to its own table
	add_node_to_neighborhood(node_to_add)
	--create a gossip to announce the adding
	gossip_changes("add", node_to_add)
	--return the neighborhood table as answer to the new node
	return neighborhood
end

--function parse_http_request: parses the payload of the HTTP request
function parse_http_request(socket)
	--print("\n\nHEADER\n\n")
	--retrieves the first line, in order to get the method
	local first_line = socket:receive("*l")
	--initializes an auxiliary variable
	local first_line_analyzer = {}
	--for every "word" separated by spaces on the first line, add the word to the aux variable
	for piece in string.gmatch(first_line, "[^ ]+") do
		table.insert(first_line_analyzer, piece)
	end
	--the method is the first word
	local method = first_line_analyzer[1]
	--the resource is the second word
	local resource = first_line_analyzer[2]
	--the HTTP version is the third
	local http_version = first_line_analyzer[3]
	local headers = {}
	--extract the headers line by line
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
	--takes the number of bytes for the body from the header "content-length"
	local bytes_left = tonumber(headers["content-length"] or headers["Content-Length"])
	-- initializes the request body read from client as empty string
	local body = nil
	--if there are bytes left
	if bytes_left then
		--print("body length = "..bytes_left)
		--retrieve the body
		body = socket:receive(bytes_left)
		--print("body = "..body)
	end
	--returns all the parsed elements
	return method, resource, http_version, headers, body
end

--REQUEST HANDLING FUNCTIONS

--function handle_get_bucket: handles a GET BUCKET request as the Coordinator of the Access Key ID
function handle_get(type_of_transaction, key)
	log:print(n.id.."handle_get: for key="..key)
	local responsibles = get_responsibles(key)
	local chosen_node_id = math.random(#responsibles)
	--log:print(n.id..": choosing responsible n. "..chosen_node_id)
	local chosen_node = responsibles[chosen_node_id]
	--construct the function to call
	local function_to_call = "distdb."..type_of_transaction.."_get"
	local rpc_ok, rpc_answer = rpc.acall(chosen_node, {function_to_call, key, value})
	if rpc_ok then
		return rpc_answer[1], rpc_answer[2]
	end
	return nil, "network problem"
end

--function handle_put_bucket: handles a PUT BUCKET request as the Coordinator of the Access Key ID
function handle_put(type_of_transaction, key, value) --TODO check about setting N,R,W on the transaction
	log:print(n.id..":handle_put: for key="..key..", value="..value)
	
	local chosen_node = nil
	
	if type_of_transaction == "consistent" then
		chosen_node = get_master(key)
	else
		local responsibles = get_responsibles(key)
		local chosen_node_id = math.random(#responsibles)
		--log:print(n.id..": choosing responsible n. "..chosen_node_id)
		chosen_node = responsibles[chosen_node_id]
	end
	--log:print(n.id..": Chosen node is "..chosen_node.id)
	--[[TESTING WRONG NODE
	if math.random(5) == 1 then
		local new_node_id = math.random(#job.nodes)
		chosen_node = job.nodes[new_node_id]
		log:print(n.id..": Chosen node changed")
	end
	]]--
	--log:print()
	--construct the function to call
	local function_to_call = "distdb."..type_of_transaction.."_put"
	local rpc_ok, rpc_answer = rpc.acall(chosen_node, {function_to_call, key, value})
	if rpc_ok then
		--if something went wrong
		if not rpc_answer[1] then
			log:print(n.id..":handle_put: something went wrong; node="..chosen_node.ip..":"..chosen_node.port.." answered=", rpc_answer[2])
		end
		return rpc_answer[1], rpc_answer[2]
	end
	log:print(n.id..":handle_put: RPC call to node="..chosen_node.ip..":"..chosen_node.port.." was unsuccessful")
	return nil, "network problem"
end


--TABLE OF FORWARDING FUNCTIONS

local forward_request = {
	["GET"] = handle_get,
	["PUT"] = handle_put,
	}


--FRONT-END FUNCTIONS

--function handle_http_message: handles the incoming messages (HTTP requests)
function handle_http_message(socket)
	--gets the client IP address and port from the socket
	local client_ip, client_port = socket:getpeername()
	--parses the HTTP message and extracts the HTTP method, the requested resource, etc.
	local method, resource, http_version, headers, body = parse_http_request(socket)
	--the resource has the format /key
	local key = string.sub(resource, 2)
	--logs
	--log:print(n.id..": resource is "..resource)
	--log:print(n.id..": requesting for "..key)

	--the value is the body if it exists
	local value = body
	--the header Type tells if the transaction is strongly consistent or eventually consistent
	local type_of_transaction = headers["Type"] or headers["type"]
	--logs
	log:print(n.id..":handle_http_message: http request parsed, a "..method.." request will be forwarded")
	log:print(n.id..":handle_http_message: key="..key..", value=", value)
	--forwards the request to a node that is responsible for this key
	local ok, answer = forward_request[method](type_of_transaction, key, tonumber(value))

	--initializes the response body, code and content type as nil
	local http_response_body = nil
	local http_response_code = nil
	local http_response_content_type = nil
	--if the call was OK
	if ok then
		--if answer exists
		if answer then
			--encode the response in JSON for HTTP transmision
			http_response_body = json.encode(answer)
		end
		--response code is 200 OK
		http_response_code = "200 OK"
		--the content is text
		http_response_content_type = "text/plain"
	--if the call was not OK
	else
		--send 409 Conflict (can be more specific)
		http_response_code = "409 Conflict"
		if answer then
			http_response_body = answer
			http_response_content_type = "text/plain"
		end
	end

	--constructs the HTTP message's first line
	local http_response = "HTTP/1.1 "..http_response_code.."\r\n"
	--if there is a response body
	if http_response_body then
		--concatenate headers "Content-Length" and "Content-Type" describing the body
		http_response = http_response..
			"Content-Length: "..#http_response_body.."\r\n"..
			"Content-Type: "..http_response_content_type.."\r\n\r\n"..http_response_body
	--else
	else
		--close the HTTP message
		http_response = http_response.."\r\n"
	end

	--send the HTTP response
	socket:send(http_response)
	--[[
	if string.sub(header,1,8) == "OPTIONS" then
		return handle_options_method(socket)
	else
		handle_post_method(socket,jsonmsg)
	end
	--]]
end

--function init: initialization of the node
function init(job)
	--if init has not been previously called
	if not init_done then
		--make the init_done flag true
		init_done = true
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
		n_replicas = 5 --TODO this should be configurable
		min_replicas_write = 3 --TODO this should be configurable
		min_replicas_read = 3 --TODO this should be configurable

		--starts the RPC server for internal communication
		rpc.server(n.port)

		--if it is the RDV node
		if job.position == 1 then
			--neighborhood is only itself
			neighborhood = {n}
		--else
		else
			--ask the RDV node for the neighborhood table
			neighborhood = rpc.call(job.nodes[1], {"distdb.add_me", n})
		end

		--gets the position from the neighborhood table
		n.position = get_position()
		--calculates the next node
		next_node = get_next_node()
		--calculates the previous node
		previous_node = get_previous_node()

		--create a gossip to announce the adding
		gossip_changes("add", n)

		--PRINTING STUFF
		--prints a initialization message
		log:print(n.id..":init: HTTP server started on port="..http_server_port)

		print_all()

		--starts a 5 second periodic pinging to the next node of the ring
		events.periodic(5, ping_others)
	end
end

--function stop: stops both servers (RPC and HTTP)
function stop()
	net.stop_server(n.port+1)
	rpc.stop_server(n.port)
end

--function paxos_operation: performs a generic operation of the Basic Paxos protocol
function paxos_operation(operation_type, key, prop_id, retries, value)
	log:print(n.id..":paxos_operation: ENTERED, "..operation_type.." for key="..key..", propID="..prop_id..", retriesLeft="..retries..", value="..value)
	--initializes boolean not_responsible
	local not_responsible = true
	--gets all responsibles for the key
	local responsibles = get_responsibles(key)
	--for all responsibles
	for i,v in ipairs(responsibles) do
		--if the ID of the node matches, make not_responsible false
		if v.id == n.id then
			not_responsible = false
			break
		end
	end
	--if the node is not responsible, return with an error message
	if not_responsible then
		return false, "wrong node"
	end
	--calculates the minimum majority of the replicas
	local min_majority = math.floor(n_replicas/2)+1
	--initialize the answers as 0
	local propose_answers = 0
	--initialize successful as false
	local successful = false
	--initialize string paxos_op_error_msg as "key is locked"
	local paxos_op_error_msg = "key is locked"
	--initialize higher_prop_id as 0
	local higher_prop_id = 0

	--if the key is not being modified right now
	if not locked_keys[key] then
		--lock the key during the operation -TODO think about this lock, is it necessary/useful?
		locked_keys[key] = true
		--initializes the acceptors group
		local acceptors = {}
		--for all responsibles
		for i,v in ipairs(responsibles) do
			--execute in parallel
			events.thread(function()
				local propose_answer = {}
				--if node ID is not the same as the node itself (avoids RPC calling itself)
				if v.id ~= n.id then
					--sends a Propose message
					local rpc_ok, rpc_answer = rpc.acall(v, {"distdb.receive_proposal", key, prop_id})
					--if the RPC call was OK
					if rpc_ok then
						propose_answer = rpc_answer
					--else (maybe network problem, dropped message) TODO also consider timeouts!
					else
						--WTF
						log:print(n.id..":paxos_operation: SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_PROPOSAL TO NODE="..v.id)
					end
				--if it is itself
				else
					--calls on "receive_proposal" internally, no need to RPC it
					propose_answer[1], propose_answer[2] = receive_proposal(key, prop_id)
				end
				if propose_answer[1] then
					log:print(n.id..":paxos_operation: Received a positive answer from node="..v.id)
					--adds the node to the acceptor's group
					table.insert(acceptors, v)
					--increments answers
					propose_answers = propose_answers + 1
					--if answers reaches the minimum majority
					if propose_answers >= min_majority then
						--trigger the unlocking of the key
						events.fire("propose_"..key)
					end
				else
					log:print(n.id..":paxos_operation: Received a negative answer from node="..v.id.." , highest prop ID=", propose_answer[2])
					if propose_answer[2] then
						higher_prop_id = math.max(higher_prop_id, propose_answer[2])
						--TODO complicated reasoning about what to do once you find the first negative answer
					end
				end
			end)
		end
		--waits until min_write replicas answer, or until paxos_propose_timeout is depleted
		successful = events.wait("propose_"..key, paxos_propose_timeout) --TODO match this with settings

		--takes a snapshot of the number of acceptors - related to the command "n_acceptors = n_acceptors + 1". see above
		--this is done because even after the triggering of event "key", acceptors
		--can continue engrossing the acceptors group
		--TODO check if necessary (maybe having more acceptors doesn't hurt - it involves
		--more messages in accept phase, though)
		local n_acceptors = #acceptors
		
		--if the proposal didn't gather the quorum needed
		if not successful then
			--if a higher prop_id was indicated by the acceptors
			if higher_prop_id > 0 then
				--propose 1 more than that prop_id
				prop_id = higher_prop_id + 1
			end
			--if the number of retries is depleted
			if retries == 0 then
				--unlocks the key
				locked_keys[key] = nil
				--returns failure
				return false, "failed at Propose phase after "..paxos_max_retries.."retries"
			--if not
			else
				--unlocks the key
				locked_keys[key] = nil
				--retry (retries--)
				return paxos_operation(operation_type, key, prop_id, retries-1, value)
			end
		end
		
		local accept_answers = 0
		
		--for all acceptors
		for i=1,n_acceptors do
			v = acceptors[i]
			--execute in parallel
			events.thread(function()
				local accept_answer = nil
				--if node ID is not the same as the node itself (avoids RPC calling itself)
				if v.id ~= n.id then
					--puts the key remotely on the others responsibles, if the put is successful
					local rpc_ok, rpc_answer = rpc.acall(v, {"distdb.receive_accept", key, prop_id, value})
					--if the RPC call was OK
					if rpc_ok then
						accept_answer = rpc_answer
					--else (maybe network problem, dropped message) TODO also consider timeouts!
					else
						--WTF
						log:print("paxos_operation: SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_ACCEPT TO NODE="..v.id)
					end
				else
					accept_answer = {receive_accept(key, prop_id, value)}
				end
				if accept_answer[1] then
					log:print(n.id..":paxos_operation: Received a positive answer from node="..v.id)
					--increments answers
					accept_answers = accept_answers + 1
					--if answers reaches the number of acceptors
					if accept_answers >= n_acceptors then
						--trigger the unlocking of the key
						events.fire("accept_"..key)
					end
				else
					log:print(n.id..":paxos_operation: Received a negative answer from node="..v.id.." , something went WRONG")
				end
			end)
		end


		--waits until min_write replicas answer, or until the paxos_accept_timeout is depleted
		successful, paxos_op_error_msg = events.wait("accept_"..key, paxos_accept_timeout) --TODO match this with settings


		--unlocks the key
		locked_keys[key] = nil
	end
	return successful, paxos_op_error_msg
end

--function consistent_put: puts a k,v and waits until all replicas assure they have a copy
function consistent_put(key, value)
	log:print(n.id..":consistent_put: ENTERED, for key="..key..", value="..value)
	--gets the master of this key
	local master, master_pos = get_master(key)
	--if the node is not the master
	if master_pos ~= n.position then
		--return with error message
		return false, "wrong master"
	end
	--initialize the answers as 0
	local answers = 0
	--initialize successful as false
	local successful = false
	--if the key is not being modified right now
	if not locked_keys[key] then
		--lock the key during the put
		locked_keys[key] = true
		--put the key locally
		events.thread(function()
			--if the "put" action is successful
			if put_local(key, value) then
				--increment answers
				answers = answers + 1
				--if answers reaches the number of replicas
				if answers >= n_replicas then --TODO adapt this to n_responsibles
					--trigger the unlocking of the key (see below. events.wait)
					events.fire(key)
				end
			end

		end)
		--for the next n - 1 nodes (the other replicas)
		for i = 1, n_replicas - 1 do
			--execute in parallel
			events.thread(function()
				local replica_pos = nil
				--the replica position in the table is master_pos + i if it is not bigger as the size of the table neighborhood
				if master_pos + i <= #neighborhood then
					replica_pos = master_pos + i
				--if it is, then it takes the first nodes (e.g. neighborhood size=10 => neighbors: 8, 9, 10, 1, 2...)
				else
					replica_pos = master_pos + i - #neighborhood
				end
				--log:print(n.id..":consistent_put: i="..i)
				--log:print(n.id..":consistent_put: replica pos="..replica_pos)
				--puts the key remotely on the replica
				local rpc_ok, rpc_answer = rpc.acall(neighborhood[replica_pos], {"distdb.put_local", key, value})
				--if the RPC call was OK
				if rpc_ok then
					--if the put is successful
					if rpc_answer[1] then
						--answers gets incremented
						answers = answers + 1
						--if answers reaches the number of replicas
						if answers >= n_replicas then
							--trigger the unlocking of the key
							events.fire(key)
						end
					end
				--else (maybe network problem, dropped message) TODO also consider timeouts!
				else
					--WTF
					log:print(n.id..":consistent_put: SOMETHING WENT WRONG ON THE RPC CALL PUT_LOCAL TO NODE="..neighborhood[replica_pos].id)
				end
			end)
		end
		--waits until all replicas answer, or until the rpc_timeout is depleted
		successful = events.wait(key, rpc_timeout) --TODO match this with settings --TODO 2 watch out with node failures, how to handle???
		--unlocks the key
		locked_keys[key] = nil
	end
	--returns the value of the variable successful
	return successful
end

--function evtl_consistent_put: puts a k,v and waits until a minimum of the replicas assure they have a copy
function evtl_consistent_put(key, value)
	log:print(n.id..":evtl_consistent_put: ENTERED, for key="..key..", value="..value)
	--initializes boolean not_responsible
	local not_responsible = true
	--gets all responsibles for the key
	local responsibles = get_responsibles(key)
	--for all responsibles
	for i,v in ipairs(responsibles) do
		--if the ID of the node matches, make not_responsible false
		if v.id == n.id then
			not_responsible = false
			break
		end
	end
	--if the node is not responsible, return with an error message
	if not_responsible then
		return false, "wrong node"
	end
	--initialize the answers as 0
	local answers = 0
	--initialize successful as false
	local successful = false

	--TODO consider min replicas and neighborhood

	--if the key is not being modified right now
	if not locked_keys[key] then
		--lock the key during the put
		locked_keys[key] = true
		--put the key locally TODO maybe this can change to a sequential approach; first node itself
		--checks the version and writes the k,v, then it writes to others
		events.thread(function()
			--if the "put" action is successful
			if put_local(key, value, n) then
				--increment answers
				answers = answers + 1
				--if answers reaches the minimum number of replicas that must write
				if answers >= min_replicas_write then
					--trigger the unlocking of the key
					events.fire(key)
				end
			end
		end)
		--for all responsibles
		for i,v in ipairs(responsibles) do
			--if node ID is not the same as the node itself (avoids RPC calling itself)
			if v.id ~= n.id then
				--execute in parallel
				events.thread(function()
					--puts the key remotely on the others responsibles, if the put is successful
					local rpc_ok, rpc_answer = rpc.acall(v, {"distdb.put_local", key, value, n})
					--if the RPC call was OK
					if rpc_ok then
						if rpc_answer[1] then
							--increment answers
							answers = answers + 1
							--if answers reaches the minimum number of replicas that must write
							if answers >= min_replicas_write then
								--trigger the unlocking of the key
								events.fire(key)
							end
						end
					--else (maybe network problem, dropped message) TODO also consider timeouts!
					else
						--WTF
						log:print(n.id..":evtl_consistent_put: SOMETHING WENT WRONG ON THE RPC CALL PUT_LOCAL TO NODE="..v.id)
					end
				end)
			end
		end
		--waits until min_write replicas answer, or until the rpc_timeout is depleted
		successful = events.wait(key, rpc_timeout) --TODO match this with settings
		--unlocks the key
		locked_keys[key] = nil
	end
	--returns the value of the variable successful
	return successful
end

--function paxos_put: performs a Basic Paxos protocol in order to put a k,v pair
function paxos_put(key, value)
	log:print(n.id..":paxos_put: ENTERED, for key="..key..", value="..value)
	--if no previous proposals have been done for this key
	if not prop_ids[key] then
		--first number to use is 1
		prop_ids[key] = 1
	end
	return paxos_operation("put", key, prop_ids[key], paxos_max_retries, value)
end

--function consistent_get: returns the value of a certain key; reads the value only from the node itself (matches with
--the behavior of consisten_put, where all replicas write always all values)
function consistent_get(key)
	log:print(n.id..":consistent_get: ENTERED, for key="..key)
	--gets the responsibles of the key
	local responsibles = get_responsibles(key)
	--for all responsibles
	for i,v in ipairs(responsibles) do
		--if the node ID is the same as the ID of the node itself
		if v.id == n.id then
			--returns the value of the key
			return true, get_local(key) --TODO maybe it is better to enclose this on a table to make it output-compatible with eventually-consistent get
		end
	end
	--if none of the responsible matched IDs with the node itself, return false with an error message
	return false, "wrong node"
end

--function consistent_get: returns the value of a certain key; reads the value from a minimum of replicas
function evtl_consistent_get(key)
	log:print(n.id..":evtl_consistent_get: ENTERED, for key="..key)
	--initializes not_responsible as false
	local not_responsible = true
	--gets the responsibles of the key
	local responsibles = get_responsibles(key)
	--for all responsibles
	for i,v in ipairs(responsibles) do
		--if the node ID is the same as the ID of the node itself
		if v.id == n.id then
			--not_responsible is false
			not_responsible = false
			--breaks the for loop
			break
		end
	end
	--if the node is not one of the responsibles
	if not_responsible then
		--returns false with an error message
		return false, "wrong node"
	end
	--initializes variables
	local answers = 0
	local answer_data = {}
	local return_data = {}
	local latest_vector_clock = {}
	local successful = false
	--for all the responsibles
	for i,v in ipairs(responsibles) do
		--execute in parallel
		events.thread(function()
			--if the ID is the same as the node itself
			if v.id == n.id then
				--gets the value locally
				answer_data[v.id] = get_local(key) --TODO deal with attemps of writing a previous version
			--if it is not the same ID as the node
			else
				--gets the value remotely with an RPC call
				local rpc_ok, rpc_answer = rpc.acall(v, {"distdb.get_local", key})
				--if the RPC call was OK
				if rpc_ok then
					answer_data[v.id] = rpc_answer[1]
				--else (maybe network problem, dropped message) TODO also consider timeouts!
				else
					--WTF
					log:print(n.id..":evtl_consistent_get: SOMETHING WENT WRONG ON THE RPC CALL GET_LOCAL TO NODE="..v.id)
				end
			end
			--if there is an answer
			if answer_data[v.id] then
				--logs
				log:print(n.id..":evtl_consistent_get: received from node="..v.id..", key="..key..", value="..answer_data[v.id].value..", enabled=", answer_data[v.id].enabled)
				--prints the vector clock
				for i2,v2 in pairs(answer_data[v.id].vector_clock) do
					log:print(n.id..":evtl_consistent_get: vector_clock=",i2,v2)
				end
				--increments answers
				answers = answers + 1
				--if answers reaches the minimum number of replicas that must read
				if answers >= min_replicas_read then
					--trigger the unlocking of the key
					events.fire(key)
				end
			end
		end)
	end
	--waits until min_read replicas answer, or until the rpc_timeout is depleted
	successful = events.wait(key, rpc_timeout) --TODO match this with settings
	--if it is not a successful read return false and an error message
	if not successful then
		return false, "timeout"
	end
	--initializes the comparison table for vector clocks
	local comparison_table = {}
	--for all answers
	for i,v in pairs(answer_data) do
		comparison_table[i] = {}
		--again for all answers (compare all against all)
		for i2,v2 in pairs(answer_data) do
			comparison_table[i][i2] = 0
			--if the IDs to be compared are different
			if i2 ~= i then
				--log:print("comparing "..i.." and "..i2)
				--checks whether the comparison was already done
				local do_comparison = false
				if not comparison_table[i2] then
					do_comparison = true
				elseif not comparison_table[i2][i] then
					do_comparison = true
				end
				--if it comparison was not yet made
				if do_comparison then
					--initialize the merged clock vector
					local merged_vector = {}
					--writes first the first vector to be merged as the winner (max = 1)
					for i3,v3 in pairs(v.vector_clock) do
						merged_vector[i3] = {value=v3, max=1}
						--log:print(i3, v3)
					end
					--log:print("then "..i2)
					--then, for all elements of the second vector
					for i4,v4 in pairs(v2.vector_clock) do
						--log:print(i4, v4)
						--if there is already an element like this in the vector
						if merged_vector[i4] then
							--compares both, if the second is bigger, max is 2
							if v4 > merged_vector[i4].value then
								merged_vector[i4] = {value=v4, max=2}
							--if they are equal, max is 0 (draw)
							elseif v4 == merged_vector[i4].value then
								merged_vector[i4].max = 0
							end
						--if there was no element, it just adds it to the vector with max = 2
						else
							merged_vector[i4] = {value=v4, max=1}
						end
					end
					--goes through the whole merged vector
					for i5,v5 in pairs(merged_vector) do
						--if all elements are =1, the first is fresher
						--if all elements are =2, the second is fresher
						--if all are equal, vectors are equal
						--if some are 2 and some are 1, nothing can be said (comparison_table=3)
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
				--logs
				--log:print("comparison_table: "..comparison_table[i][i2])
			end
		end
	end
	--for all comparisons
	for i,v in pairs(comparison_table) do
		for i2,v2 in pairs(v) do
			--if the comparison = 1, deletes the second answer
			if v2 == 1 then
				answer_data[i2] = nil
				--log:print("deleting answer from "..i2.." because "..i.." is fresher")
			--if the comparison = 2, deletes the first answer
			elseif v2 == 2 then
				answer_data[i] = nil
				--log:print("deleting answer from "..i.." because "..i2.." is fresher")
			end
			--TODO WHAT IF they are equal? i think im not considering this case
		end
	end
	--insert the info in the return data
	for i,v in pairs(answer_data) do
		log:print(n.id..":evtl_consistent_get: remaining answer=", i, v.value)
		table.insert(return_data, v)
	end
	--returns
	return true, return_data
end

--function receive_proposal: receives and answers to a "Propose" message, used in Paxos
function receive_proposal(key, prop_id)
	log:print(n.id..": Entered in RECEIVE PROPOSAL for key "..key..", prop_id="..prop_id)
	--adding a random failure to simulate failed local transactions
	if math.random(5) == 1 then
		log:print(n.id..": NOT accepting Propose for key: "..key)
		return false
	end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.id..": NOT accepting Propose for key, wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not db_table[key] then
		db_table[key] = {enabled=true, vector_clock={}} --check how to make compatible with vector_clock
	--if it exists
	elseif db_table[key].prop_id and db_table[key].prop_id >= prop_id then
		return false, db_table[key].prop_id
	end
	db_table[key].prop_id = prop_id
	return true
end

--function receive_accept: receives and answers to a "Accept!" message, used in Paxos
function receive_accept(key, prop_id, value)
	log:print(n.id..": Entered in RECEIVE ACCEPT for key "..key)
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.id..": NOT accepting Accept! for key, wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not db_table[key] then
		log:print(n.id..":receive_accept: BIZARRE! wrong key, key does not exist")
		return false, "BIZARRE! wrong key, key does not exist"
	--if it exists
	elseif db_table[key].prop_id > prop_id then
		log:print(n.id..":receive_accept: REJECTED, higher prop_id")
		return false, "higher prop_id"
	elseif db_table[key].prop_id < prop_id then
		log:print(n.id..":receive_accept: BIZARRE! lower prop_id")
		return false, "BIZARRE! lower prop_id"
	end
	log:print(n.id..": Telling learners about key: "..key..", value: "..value..", enabled: ", db_table[key].enabled, "propID:"..prop_id)
	local responsibles = get_responsibles(key)
	for i,v in ipairs(responsibles) do
		if v.id == n.id then
			events.thread(function()
				put_local(key, value)
			end)
		else
			--Normally this will be replaced in order to not make a WRITE in RAM/Disk everytime an Acceptor
			--sends put_local to a Learner
			events.thread(function()
				rpc.call(v, {"distdb.put_local", key, value})
			end)
		end
	end
	return true
end

--function put_local: writes a k,v pair. TODO should be atomic? is it?
function put_local(key, value, src_write)
	log:print(n.id..": Entered in LOCAL PUT for key "..key)
	--TODO how to check if the source node is valid?
	--adding a random failure to simulate failed local transactions
	--if math.random(5) == 1 then
	--	log:print(n.id..": NOT writing key: "..key)
	--	return false, "404"
	--end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.id..": NOT writing key, wrong key type")
		return false, "wrong key type"
	end
	--if value is not a string or a number, dont accept the transaction
	if type(value) ~= "string" and type(value) ~= "number" then
		log:print(n.id..": NOT writing key, wrong value type")
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
	log:print(n.id..": writing key: "..key..", value: "..value..", enabled: ", db_table[key].enabled, "vector_clock:")
	for i,v in pairs(db_table[key].vector_clock) do
		log:print(n.id..":",i,v)
	end
	return true
end

function get_local(key)
	--adding a random failure to simulate failed local transactions
	--if math.random(10) == 1 then
	--	return nil
	--end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	return db_table[key]
end

