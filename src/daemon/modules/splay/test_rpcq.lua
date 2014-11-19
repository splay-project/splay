require"splay.base"
rpc = require"splay.rpcq"
function pong()
	return "pong"
end
events.run(function()
	print("run")
    local rpc_server = rpc.server(30001)
	assert(rpc_server)
	local pong_rep = rpc.call({ip="127.0.0.1",port=30001}, {"pong"})
	assert(pong_rep)	
	print("pong reply:", pong_rep)
	events.exit()
	os.exit()
end)