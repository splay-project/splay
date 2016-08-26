--[[
       Splay Client Commands ### v ###
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

-- RPC library
rpc = require"splay.rpc"
--local log                = require"splay.log"
--local l_o                = log.new(3, "[school]")

-- accept incoming RPCs
rpc.server(job.me.port)

function call_me(position)
	print("I received an RPC from node "..position)
end

-- our main function
function SPLAYschool()
	-- print bootstrap information about local node
	local nodes = job.get_live_nodes() --OR the old form: job.nodes
	for k,v in pairs(job) do
          print(k, " :: ", v)
	end
	print("I'm "..job.me.ip..":"..job.me.port)
	print("My position in the list is: "..job.position)
	print("List type is '"..job.list_type.."' with "..#nodes.." nodes")

	-- wait for all nodes to be started (conservative)
	events.sleep(5)

	-- send RPC to random node of the list
	rpc.call(nodes[1], {"call_me", job.position})

	-- you can also spawn new threads (here with an anonymous function)
	events.thread(function() print("Bye bye") end)

	-- wait for messages from other nodes
	events.sleep(5)
	-- explicitely exit the program (necessary to kill RPC server)
	os.exit()
end
-- create thread to execute the main function
events.thread(SPLAYschool)
-- start the application
events.run()

-- now, you can watch the logs of your job and enjoy ;-)
-- try this job with multiple splayds and different parameters
