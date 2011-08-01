--[[
       Splay Client Commands ### v1.1 ###
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

-- SPLAYschool tutorial

-- BASE libraries (threads, events, sockets, ...)
require"splay.base"
distdb = require"splay.distdb"
local crypto = require"crypto"
--local urpc = require"splay.urpc"
local rpc = require"splay.rpc"
local counter = 5


rpc.server(job.me.port)

function print_hello()
	log:print("I'm "..job.me.ip..":"..job.me.port)
	counter = counter + 1
	return "counter is equal "..counter
end

events.loop(function()
	math.randomseed(job.me.port)
	distdb.init(job)
	--[[
	--TESTING PUT AND GET
	distdb.put("3", 6)
	distdb.put("hello", "10")
	a = distdb.get("3")
	b = distdb.get("hello")
	print(a,b)
	--]]
	--TESTING NEIGHBORHOOD CONSTRUCTION
	events.sleep(4)
	if job.position == 1 then
		local key = crypto.evp.digest("sha1",math.random(100000))
		for i=1,10 do
			log:print("Key is "..key)
			local master = distdb.get_master(key)
			log:print("Master is "..master.id)
				--[[
				if math.random(5) == 1 then
					master = distdb.get_master(re_key)
					log:print("Master changed to "..master.id)
				end
				--]]
			log:print()
			local answer = rpc.call(master, {"distdb.consistent_put", key, 1})
			log:print("")
			log:print("put successfully done? ", answer)
			log:print("")
			events.sleep(20)
		end
	end
	--]]
	--[[
	--TESTING ONE WAY URPC
	local statss = urpc.show_stats()
	log:print(job.position..", messages:"..statss[1])
	log:print(job.position..", replied:"..statss[2])
	if job.position == 1 then
		events.sleep(3)
		log:print("number of nodes: "..#job.nodes)
		local node_to_ask = math.random(#job.nodes)
		log:print("asking node "..node_to_ask)
		urpc.call(job.nodes[node_to_ask], "print_hello")
		events.sleep(5)
		log:print("=====")
		urpc.acall_noack(job.nodes[node_to_ask], "print_hello")
	end
	events.sleep(20)
	statss = urpc.show_stats()
	log:print(job.position..", messages:"..statss[1])
	log:print(job.position..", replied:"..statss[2])
	os.exit()
	--]]
end)

-- now, you can watch the logs of your job and enjoy ;-)
-- try this job with multiple splayds and different parameters

