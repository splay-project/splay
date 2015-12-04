require"splay.base"
local rpc=require"splay.rpc"
local misc=require""splay.misc""
local crypto=require""crypto""
rpc.server(job.me.port)
me = {}
me.peer = job.me
M = 32
function compute_hash(o)
	return tonumber(string.sub(crypto.evp.new("sha1"):digest(o), 1, M/4), 16)
end
me.age = 0

me.id = job.position
me.payload = {}
PSS = {
	view = {},
	view_copy = {},

	c = 10,

	exch = 5,
	H = 1,

}

function main()

		PSS.set_parameters(60, 5, 3)
		PSS.startPSS()




end
events.thread(main)
events.run()