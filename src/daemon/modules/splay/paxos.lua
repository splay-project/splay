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
module("splay.paxos")

--authoring info
_COPYRIGHT   = "Copyright 2011 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Paxos functions."
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

--function shorten_id: returns only the first 5 hexadigits of a ID string
function shorten_id(id)
	return string.sub(id, 1, 5)..".."
end

--FRONT-END FUNCTIONS

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
		--stores also the first 5 hexadigits of the ID for better printing
		n.short_id = string.sub(n.id, 1, 5)..".."

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
		log:print(n.short_id..":init: HTTP server started on port="..http_server_port)

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
	log:print(n.short_id..":paxos_operation: ENTERED, "..operation_type.." for key="..shorten_id(key)..", propID="..prop_id..", retriesLeft="..retries..", value=", value)
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

	--if the key is being modified right now
	if locked_keys[key] then
		return false, "key is locked"
	end

	--lock the key during the operation -TODO think about this lock, is it necessary/useful?
	locked_keys[key] = true
	--initialize successful as false
	local successful = false
	--initialize string paxos_op_error_msg as nil
	local paxos_op_error_msg = nil
	--calculates the minimum majority of the replicas
	local min_majority = math.floor(n_replicas/2)+1
	--initialize the answers as 0
	local propose_answers = 0
	--initialize newest_prop_id as 0
	local newest_prop_id = 0
	
	local newest_value = nil
	
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
					log:print(n.short_id..":paxos_operation: SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_PROPOSAL TO NODE="..v.short_id)
				end
			--if it is itself
			else
				--calls on "receive_proposal" internally, no need to RPC it
				propose_answer[1], propose_answer[2], propose_answer[3] = receive_proposal(key, prop_id)
			end
			if propose_answer[1] then
				if propose_answer[3] then
					log:print(n.short_id..":paxos_operation: Received a positive answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=", propose_answer[3].value)
				else
					log:print(n.short_id..":paxos_operation: Received a positive answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=")
				end
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
				if propose_answer[3] then
					log:print(n.short_id..":paxos_operation: Received a negative answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=", propose_answer[3].value)
				else
					log:print(n.short_id..":paxos_operation: Received a negative answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=")
				end
			end
			if propose_answer[2] then
				--TODO complicated reasoning about what to do once you find the first negative answer
				if propose_answer[2] > newest_prop_id then
					newest_prop_id = propose_answer[2]
					if propose_answer[3] then
						newest_value = propose_answer[3]
					end
				end
			end
			if newest_value then
				log:print(n.short_id..":paxos_operation: newest_prop_id="..newest_prop_id..", newest_value=", newest_value.value)
			else
				log:print(n.short_id..":paxos_operation: newest_prop_id="..newest_prop_id..", newest_value=")
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
		if newest_prop_id > 0 then
			--propose 1 more than that prop_id
			prop_id = newest_prop_id + 1
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

	if operation_type == "get" then
		return true, {newest_value}
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
					log:print("paxos_operation: SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_ACCEPT TO NODE="..v.short_id)
				end
			else
				accept_answer = {receive_accept(key, prop_id, value)}
			end
			if accept_answer[1] then
				log:print(n.short_id..":paxos_operation: Received a positive answer from node="..v.short_id)
				--increments answers
				accept_answers = accept_answers + 1
				--if answers reaches the number of acceptors
				if accept_answers >= n_acceptors then
					--trigger the unlocking of the key
					events.fire("accept_"..key)
				end
			else
				log:print(n.short_id..":paxos_operation: Received a negative answer from node="..v.short_id.." , something went WRONG")
			end
		end)
	end


	--waits until min_write replicas answer, or until the paxos_accept_timeout is depleted
	successful, paxos_op_error_msg = events.wait("accept_"..key, paxos_accept_timeout) --TODO match this with settings

	--unlocks the key
	locked_keys[key] = nil
	return successful, paxos_op_error_msg
end


--BACK-END FUNCTIONS

--function receive_proposal: receives and answers to a "Propose" message, used in Paxos
function receive_proposal(key, prop_id)
	log:print(n.short_id..":receive_proposal: ENTERED, for key="..shorten_id(key)..", prop_id="..prop_id)
	--adding a random failure to simulate failed local transactions
	if math.random(5) == 1 then
		log:print(n.short_id..":receive_proposal: RANDOMLY NOT accepting Propose for key="..shorten_id(key))
		return false
	end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.short_id..":receive_proposal: NOT accepting Propose for key, wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not db_table[key] then
		db_table[key] = {enabled=true, vector_clock={}} --check how to make compatible with vector_clock
	--if it exists
	elseif db_table[key].prop_id and db_table[key].prop_id >= prop_id then
		--TODO maybe to send the value on a negative answer is not necessary
		return false, db_table[key].prop_id, db_table[key]
	end
	local old_prop_id = db_table[key].prop_id
	db_table[key].prop_id = prop_id
	return true, old_prop_id, db_table[key]
end

--function receive_accept: receives and answers to a "Accept!" message, used in Paxos
function receive_accept(key, prop_id, value)
	log:print(n.short_id..":receive_accept: ENTERED, for key="..shorten_id(key)..", prop_id="..prop_id..", value="..value)
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(n.short_id..": NOT accepting Accept! wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist
	if not db_table[key] then
		--BIZARRE: because this is not meant to happen (an Accept comes after a Propose, and a record for the key
		--is always created at a Propose)
		log:print(n.short_id..":receive_accept: BIZARRE! wrong key="..shorten_id(key)..", key does not exist")
		return false, "BIZARRE! wrong key, key does not exist"
	--if it exists, and the locally stored prop_id is bigger than the proposed prop_id
	elseif db_table[key].prop_id > prop_id then
		--reject the Accept! message
		log:print(n.short_id..":receive_accept: REJECTED, higher prop_id")
		return false, "higher prop_id"
	--if the locally stored prop_id is smaller than the proposed prop_id
	elseif db_table[key].prop_id < prop_id then
		--BIZARRE: again, Accept comes after Propose, and a later Propose can only increase the prop_id
		log:print(n.short_id..":receive_accept: BIZARRE! lower prop_id")
		return false, "BIZARRE! lower prop_id"
	end
	log:print(n.short_id..":receive_accept: Telling learners about key="..shorten_id(key)..", value="..value..", enabled=", db_table[key].enabled, "propID="..prop_id)
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

--to be replaced with app function
function receive_learn()
end
