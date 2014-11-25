require"splay.base"
local rpc = require"splay.rpc"
local l_o = log.new(3, "[test_socket_threads]")
c=0
--check that the server thread correctly yields to the periodic thread
events.run(function()
	local rpc_server_thread = rpc.server(30001)
	events.periodic(1,function()
		l_o:print("c="..c)
		c=c+1
	end)
end)