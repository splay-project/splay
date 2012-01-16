--- SPLAYschool tutorial

-- BASE libraries (threads, events, sockets, ...)
require"splay.base"

-- RPC library
rpc = require"splay.rpc"

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
  log:print("List type is '"..job.list_type.."' with "..#job.nodes.." nodes")

  -- wait for all nodes to be started (conservative)
  events.sleep(5)

  -- send RPC to random node of the list
  rpc.call(job.nodes[1], {"call_me", job.position})

  -- you can also spawn new threads (here with an anonymous function)
  events.thread(function() log:print("Bye bye") end)

  -- wait for messages from other nodes
  events.sleep(5)

  -- explicitly exit the program (necessary to kill RPC server)
  os.exit()
end

-- create thread to execute the main function
events.thread(SPLAYschool)

-- start the application
events.loop()

-- now, you can watch the logs of your job and enjoy ;-)
-- try this job with multiple splayds and different parameters
