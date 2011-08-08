--TEST DISTDB MODULE

require"splay.base"
distdb = require"splay.distdb"
local crypto = require"crypto"
--local urpc = require"splay.urpc"
local rpc = require"splay.rpc"
local counter = 5


events.loop(function()
	distdb.init(job)
	if job.position == 10 then
		events.sleep(15)
		log:print(job.me.port..": im goin DOOOOWN!!!")
		os.exit()
	end
end)

