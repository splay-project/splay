require"splay.base"
rpc = require"splay.rpc"
function pong()
	return "pong"
end
events.run(function()
	print("run")
    rpc.server(30001)
	local pong_rep = rpc.call({ip="127.0.0.1",port=30001}, {"pong"})	
	print("pong reply:", pong_rep)
	events.exit()
	os.exit()
end)