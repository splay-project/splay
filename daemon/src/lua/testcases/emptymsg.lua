require"splay.base"
rpc = require"splay.rpc"
rpc.server(job.me.port)
events.thread(function()
	local msg="before\n\nafter"
	log:print(msg)
	events.exit()
end)
events.loop()
