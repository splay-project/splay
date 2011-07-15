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

module("splay.distdb")

_COPYRIGHT   = "Copyright 2011 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Distributed DB functions."
_VERSION     = "0.99.0"

local db_table = {}

local init_done = false

--=========== FROM DIST-DB.LUA BEGINNING
--function calculate_id: calculates the node ID from ID and port
local function calculate_id(node)
	return crypto.evp.digest("sha1",node.ip..node.port)
end

--function get_master: looks for the master of a given ID
local function get_master(id)
	--TODO AQUI ME QUEDE
	--the master is initialized as equal to the last node
	local master = neighborhood[#neighborhood]
	--for all the neighbors
	for i,v in ipairs(neighborhood) do
		--compares the id with the id of the node
		local compare = bighex_compare(v.id, id)
		--if id is bigger
		if (compare == 1) and (i ~= 1) then
			master = v
		end
	end
	--returns the closest node
	return master
end

--function print_me: prints the IP address, port, and ID of the node
function print_me()
	log:print("ME",n.ip, n.port, n.id)
end

--function print_node: prints the IP address, port, and ID of a given node
function print_node(node)
	log:print(node.ip, node.port, node.id)
end

--=========== FROM DIST-DB.LUA END



function init()
	if not init_done then
		init_done = true
		--TODO add node to the db network
		--TODO start pinging processes
		--TODO the rest of init
		--takes IP address and port from job.me
		n = {ip=job.me.ip, port=job.me.port}
		--initializes the randomseed with the port
		--math.randomseed(n.port) CHECK I think i dont need this anymore
		--calculates the ID by hashing the IP address and port
		n.id = calculate_id(job.me)
		--initializes the neighborhood as an empty table
		neighborhood = {}
		--for all nodes on job.nodes TODO take care of CHURNING
		for _,v in ipairs(job.nodes) do
			--copies IP address, port and calculates the ID from them
			table.insert(neighborhood, {
				ip = v.ip,
				port = v.port,
				id = calculate_id(v)
			})
		end
		--sorts the elements of the table by their ids
		table.sort(neighborhood, function(a,b) return a.id<b.id end)
		--server listens through the rpc port + 1
		local http_server_port = n.port+1
		--puts the server on listen
		net.server(http_server_port, handle_http_message)

		--initializes db_table
		db_table = {}

		--starts the RPC server for internal communication
		rpc.server(n.port)

		--PRINTING STUFF
		--prints a initialization message
		print("HTTP server - Started on port "..http_server_port)
		print_me()
		for _,v in ipairs(neighborhood) do
			print_node(v)
		end
		for _,v in ipairs(neighborhood) do
			log:print("\t"..(tonumber(v.port)+1)..",")
		end
	end
end

function put(key, value)
		--TODO the content of this function
	return version
end

--function put_local: writes a k,v pair. TODO should be atomic? is it?
local function put_local(key, value)
	--if key is not a string, dont accept the transaction
	if type(key) ~= "string" then
		return false, "wrong key type"
	end
	--if value is not a string or a number, dont accept the transaction
	if type(value) ~= "string" and type(value) ~= "number" then
		return false, "wrong value type"
	end
	--if the k,v pair doesnt exist, create it with version=1, enabled=true
	if not db_table[key] then
		db_table[key] = {value=value, version=1, enabled=true}
	else
	--else, replace the value and increase the version
		db_table[key].value=value
		db_table[key].version=db_table[key].version + 1
		--TODO handle enabled and versions
	end
	db_table[key] = value
	return true, version
	--print("key: "..key..", value: "..value)
end

local function get_local(key)
	return db_table[key]
end

