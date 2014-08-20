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

-- RPC library
rpc = require"splay.rpc"
require "hello"


-- accept incoming RPCs
rpc.server(job.me.port)

function call_me(position)
        log:print("I received an RPC from node "..position)
end

-- our main function
function SPLAYschool()
        -- print bootstrap information about local node
        log:print("I'm "..job.me.ip..":"..job.me.port)
        log:print("My position in the list is: "..job.position)
        --log:print("List type is '"..job.list_type.."' with "..job.nodes.." nodes")

        -- wait for all nodes to be started (conservative)
        events.sleep(3)

		log:print("Hello from C: "..hello.hello())
		log:print("Finish the job")
        -- send RPC to random node of the list
        --rpc.call(job.nodes[1], {"call_me", job.position})

        -- you can also spawn new threads (here with an anonymous function)
        --events.thread(function() log:print("Bye bye") end)

        -- wait for messages from other nodes
        events.sleep(3)
                                                                                                                                                                                    
        -- explicitely exit the program (necessary to kill RPC server)                                                                                                              
        os.exit()                                                                                                                                                                   
end                                                                                                                                                                                 
                                                                                                                                                                                    
-- create thread to execute the main function                                                                                                                                       
events.thread(SPLAYschool)                                                                                                                                                          
                                                                                                                                                                                    
-- start the application                                                                                                                                                            
events.loop()                                                                                                                                                                       
                                                                                                                                                                                    
-- now, you can watch the logs of your job and enjoy ;-)                                                                                                                            
-- try this job with multiple splayds and different parameters  
