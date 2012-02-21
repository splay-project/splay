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
local base = _G --TODO is this really useful?


--naming the module
module("splay.paxos")

--authoring info
_COPYRIGHT   = "Copyright 2011-2012 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Paxos functions."
_VERSION     = "0.99.1"


--LOCAL VARIABLES

--rpc_timeout is the time in seconds that a node waits for an answer from another node on any rpc call
local rpc_timeout = 15
--paxos_propose_timeout is the time in seconds that a Proposer waits that all Acceptors answer a Propose message
local paxos_propose_timeout = 15
--paxos_accept_timeout is the time in seconds that a Proposer waits that all Acceptors answer an Accept message
local paxos_accept_timeout = 15
--paxos_learn_timeout is the time in seconds that an Acceptor waits that all Learners answer a Learn message
local paxos_learn_timeout = 15
--init_done is a flag to avoid double initialization
local init_done = false
--prop_ids holds the Proposal IDs for Paxos operations (used by Proposer)
local prop_ids = {}
--paxos_max_retries is the maximum number of times a Proposer can try a Proposal
local paxos_max_retries = 5 --TODO maybe this should match with some distdb settings object


--LOCAL FUNCTIONS

--function shorten_id: returns only the first 5 hexadigits of a ID string (for better printing)
local function shorten_id(id)
	return string.sub(id, 1, 5)..".."
end

--FRONT-END FUNCTIONS

function paxos_read(key, prop_id, peers, retries)
	return paxos_operation("read", key, prop_id, peers, retries)
end

function paxos_write(key, prop_id, peers, retries, value) --AQUI ME QUEDE: TODO: WEIRD ERROR WITH paxos_operation
	return paxos_operation("write", key, prop_id, peers, retries, value)
end

--function paxos_operation: performs a generic operation of the Basic Paxos protocol
local function paxos_operation(operation_type, key, prop_id, peers, retries, value)
	--logs entrance to the function
	log:print("paxos_"..operation_type..": ENTERED, for key="..shorten_id(key)..", propID="..prop_id..", retriesLeft="..retries..", value=", value)
	--prints all the peers
	for i,v in ipairs(peers) do
		log:print("paxos_"..operation_type..": peer="..shorten_id(v.id))
	end

	--initialize successful as false
	local successful = false
	--initialize string paxos_op_error_msg as nil
	local paxos_op_error_msg = nil
	--calculates the minimum majority for the peers
	local min_majority = math.floor(#peers/2)+1
	--initialize the answers as 0
	local propose_answers = 0
	--initialize newest_prop_id as 0
	local newest_prop_id = 0
	--initialize newest_value as nil
	local newest_value = nil
	--initializes the acceptors group
	local acceptors = {}
	--for all responsibles
	for i,v in ipairs(peers) do
		--execute in parallel
		events.thread(function()
			local propose_answer = {}
			--sends a Propose message
			local rpc_ok, rpc_answer = send_proposal(v, key, prop_id)
			--if the RPC call was OK
			if rpc_ok then
				propose_answer = rpc_answer
			--else (maybe network problem, dropped message) TODO also consider timeouts!
			else
				--WTF
				log:print("paxos_"..operation_type..": SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_PROPOSAL TO NODE="..v.short_id)
			end
			--if the answer was positive
			if propose_answer[1] then
				--log the positive answer
				if propose_answer[3] then
					--prints a value if there is one
					log:print("paxos_"..operation_type..": Received a positive answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=", propose_answer[3].value)
				else
					--if not, doesn't print value
					log:print("paxos_"..operation_type..": Received a positive answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=")
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
					log:print("paxos_"..operation_type..": Received a negative answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=", propose_answer[3].value)
				else
					log:print("paxos_"..operation_type..": Received a negative answer from node="..v.short_id.." , highest prop ID=", propose_answer[2], "value=")
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
				log:print("paxos_"..operation_type..": newest_prop_id="..newest_prop_id..", newest_value=", newest_value.value)
			else
				log:print("paxos_"..operation_type..": newest_prop_id="..newest_prop_id..", newest_value=")
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
			--returns failure
			return false, "failed at Propose phase after "..paxos_max_retries.."retries"
		--if not
		else
			--retry (retries--)
			return paxos_operation(operation_type, key, prop_id, peers, retries-1, value)
		end
	end

	if operation_type == "read" then
		return true, {newest_value}
	end


	local accept_answers = 0
	--for all acceptors
	for i=1,n_acceptors do
		v = acceptors[i]
		--execute in parallel
		events.thread(function()
			local accept_answer = nil
			--puts the key remotely on the others responsibles, if the put is successful
			local rpc_ok, rpc_answer = send_accept(v, key, prop_id, peers, value)
			--if the RPC call was OK
			if rpc_ok then
				accept_answer = rpc_answer
			--else (maybe network problem, dropped message) TODO also consider timeouts!
			else
				--WTF
				log:print("paxos_"..operation_type..": SOMETHING WENT WRONG ON THE RPC CALL RECEIVE_ACCEPT TO NODE="..v.short_id)
			end
			if accept_answer[1] then
				log:print("paxos_"..operation_type..": Received a positive answer from node="..v.short_id)
				--increments answers
				accept_answers = accept_answers + 1
				--if answers reaches the number of acceptors
				if accept_answers >= n_acceptors then
					--trigger the unlocking of the key
					events.fire("accept_"..key)
				end
			else
				log:print("paxos_"..operation_type..": Received a negative answer from node="..v.short_id.." , something went WRONG")
			end
		end)
	end


	--waits until min_write replicas answer, or until the paxos_accept_timeout is depleted
	successful, paxos_op_error_msg = events.wait("accept_"..key, paxos_accept_timeout) --TODO match this with settings

	return successful, paxos_op_error_msg
end

--to be replaced if paxos is used as a library inside a library
function send_proposal(v, key, prop_id)
	--logs entrance to the function
	log:print("send_proposal: ENTERED, for node="..shorten_id(v.id)..", key="..shorten_id(key)..", propID="..prop_id)
	return rpc.acall(v, {"paxos.receive_proposal", key, prop_id})
end

function send_accept(v, key, prop_id, peers, value)
	--logs entrance to the function
	log:print("send_accept: ENTERED, for node="..shorten_id(v.id)..", key="..shorten_id(key)..", propID="..prop_id..", value="..value)
	for i2,v2 in ipairs(peers) do
		log:print("send_accept: peers: node="..shorten_id(v2.id))
	end
	return rpc.acall(v, {"paxos.receive_accept", key, prop_id, peers, value})
end

function send_learn(v, key, value)
	--logs entrance to the function
	log:print("send_learn: ENTERED, for node="..shorten_id(v.id)..", key="..shorten_id(key)..", value="..value)
	return rpc.acall(v, {"paxos.receive_learn", key, value})
end

--BACK-END FUNCTIONS
--function receive_proposal: receives and answers to a "Propose" message, used in Paxos
function receive_proposal(key, prop_id)
	log:print("receive_proposal: ENTERED, for key="..shorten_id(key)..", prop_id="..prop_id)
	--adding a random failure to simulate failed local transactions
	if math.random(5) == 1 then
		log:print("receive_proposal: RANDOMLY NOT accepting Propose for key="..shorten_id(key))
		return false
	end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print("receive_proposal: NOT accepting Propose for key, wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not paxos_db[key] then
		paxos_db[key] = {}
	--if it exists
	elseif paxos_db[key].prop_id and paxos_db[key].prop_id >= prop_id then
		--TODO maybe to send the value on a negative answer is not necessary
		return false, paxos_db[key].prop_id, paxos_db[key]
	end
	local old_prop_id = paxos_db[key].prop_id
	paxos_db[key].prop_id = prop_id
	return true, old_prop_id, paxos_db[key]
end

--function receive_accept: receives and answers to a "Accept!" message, used in Paxos
function receive_accept(key, prop_id, peers, value)
	log:print("receive_accept: ENTERED, for key="..shorten_id(key)..", prop_id="..prop_id..", value="..value)
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print(" NOT accepting Accept! wrong key type")
		return false, "wrong key type"
	end

	--if the k,v pair doesnt exist
	if not paxos_db[key] then
		--BIZARRE: because this is not meant to happen (an Accept comes after a Propose, and a record for the key
		--is always created at a Propose)
		log:print("receive_accept: BIZARRE! wrong key="..shorten_id(key)..", key does not exist")
		return false, "BIZARRE! wrong key, key does not exist"
	--if it exists, and the locally stored prop_id is bigger than the proposed prop_id
	elseif paxos_db[key].prop_id > prop_id then
		--reject the Accept! message
		log:print("receive_accept: REJECTED, higher prop_id")
		return false, "higher prop_id"
	--if the locally stored prop_id is smaller than the proposed prop_id
	elseif paxos_db[key].prop_id < prop_id then
		--BIZARRE: again, Accept comes after Propose, and a later Propose can only increase the prop_id
		log:print("receive_accept: BIZARRE! lower prop_id")
		return false, "BIZARRE! lower prop_id"
	end
	log:print("receive_accept: Telling learners about key="..shorten_id(key)..", value="..value..", enabled=", paxos_db[key].enabled, "propID="..prop_id)
	for i,v in ipairs(peers) do
		events.thread(function()
			send_learn(v, key, value)
		end)
	end
	return true
end

--to be replaced with app function
function receive_learn(key, value)
	log:print("receive_learn: ENTERED, for key="..shorten_id(key)..", value="..value)
	--TODO how to check if the source node is valid?
	--adding a random failure to simulate failed local transactions
	--if math.random(5) == 1 then
	--	log:print(n.short_id..": NOT writing key: "..key)
	--	return false, "404"
	--end
	--adding a random waiting time to simulate different response times
	events.sleep(math.random(100)/100)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		log:print("receive_learn: NOT writing key, wrong key type")
		return false, "wrong key type"
	end
	--if value is not a string or a number, dont accept the transaction
	if type(value) ~= "string" and type(value) ~= "number" then
		log:print("receive_learn: NOT writing key, wrong value type")
		return false, "wrong value type"
	end
--[[
--TODO write only when there is a quorum
	if not src_write then
		src_write = {id="version"} --for compatibility with consistent_put
	end
--]]
	--if the k,v pair doesnt exist, create it with a new vector clock, enabled=true
	if not paxos_db[key] then
		paxos_db[key] = {}
	end
	--replace the value
	paxos_db[key].value=value

	log:print("receive_learn: writing key="..shorten_id(key)..", value: "..value)
	return true
end
