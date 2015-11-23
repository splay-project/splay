require"splay.base"
local rpc = require"splay.urpc"
local log = require"splay.log"
local l_o = log.new(3, "[test_urpc_server]")
function pong()
	return "pong"
end
events.run(function()
	local port=30001
	l_o:print("Start URPC server on port 30001")
	local rpc_server_thread = rpc.server(port)
	l_o:print("Status of RPC_SERVER_THREAD:", rpc_server_thread)
	l_o:print("Issuing RPC call")	
	local pong_rep, err= rpc.call({ip="127.0.0.1",port=port}, {"pong"})	
	l_o:print("pong reply:", pong_rep, "err", err)
	assert(pong_rep=="pong")
	assert(err==nil)
	print("TEST_OK")
	events.exit()
end)
