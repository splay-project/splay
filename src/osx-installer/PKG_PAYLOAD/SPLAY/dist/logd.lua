--[[
-- Small Lua log daemon to test applications.
--]]

require"splay.base"
net = require"splay.net"

port = 10002

net.server(function(s)
		local ip = assert(s:getpeername())					
		while true do
			print(ip..": "..assert(s:receive("*l")))
		end
	end, port)

events.loop()
