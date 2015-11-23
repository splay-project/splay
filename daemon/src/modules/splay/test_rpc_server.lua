require"splay.base"
local rpc = require"splay.rpc"
local log = require"splay.log"
local l_o = log.new(3, "[test_rpc_server]")
function pong()
	return "pong"
end
events.run(function()
	local port=30001
	local rpc_server_thread = rpc.server(port)
	local pong_rep, err= rpc.call({ip="127.0.0.1",port=port}, {"pong"})	
	assert(pong_rep=="pong")
	assert(err==nil)
	print("TEST_OK")
	events.exit()
end)
