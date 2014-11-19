require"splay.base"
local rpc = require"splay.rpc"
local log = require"splay.log"
local l_o = log.new(3, "[test_rpc]")
function pong()
	return "pong"
end
events.run(function()
	log:print("run")
    rpc.server(30001)
	local pong_rep = rpc.call({ip="127.0.0.1",port=30001}, {"pong"})	
	log:print("pong reply:", pong_rep)
	events.exit()
	os.exit()
end)