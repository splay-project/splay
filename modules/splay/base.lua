--[[
-- Load basic splay functions. Anyway, they are already loaded by the splayd,
-- there is no memory to win, not loading them directly.
--]]

coxpcall = require"splay.coxpcall"
pcall = coxpcall.pcall
xpcall = coxpcall.xpcall

-- socket_events is a global too
socket = require"splay.socket"

events = require"splay.events"
log = require"splay.log"
misc = require"splay.misc"

if job and job.position and type(job.position) == "number" then
	math.randomseed(misc.time() + (job.position * 100000))
else
	math.randomseed(misc.time() * 10000)
end

return true
