require"splay.base"
local misc=require"splay.misc"
local log = require"splay.log"
local l_o = log.new(3, "[test_events_sleep]")

events.run(function()
	l_o:print("run")
	l_o:print("Going to nap for 2s")
	local now= misc.time()
	events.sleep(2)
	l_o:print("Slept 2s")
	local nap=misc.time() - now
	l_o:print("napped for:",nap)
	assert(nap>2, "Slept for less than expected time")
	events.exit()
	l_o:print("exiting")
	os.exit()
end)