require"splay.base"
local rpc = require"splay.rpcq"
local log = require"splay.log"
local l_o = log.new(3, "[test_rpcq]")
function pong()
	return "pong"
end
events.run(function()	
	l_o:print("run")
    local rpc_server = rpc.server(30001)
	assert(rpc_server)	
	local pong_rep = rpc.call({ip="127.0.0.1",port=30001}, {"pong"})
	assert(pong_rep)	
	assert("pong"==pong_rep)
	events.exit()
	l_o:print("exiting")
	os.exit()
end)