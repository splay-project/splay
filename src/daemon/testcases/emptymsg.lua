require"splay.base"
rpc = require"splay.rpc"
rpc.server(job.me.port)
events.thread(function()
	local msg="some test here\n".."\t\n"
	log:print(msg)
	events.exit()
end)
events.loop()
