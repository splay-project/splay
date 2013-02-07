require"splay.base"
local rpc = require"splay.rpc"
require"logger"

rpc.server(33500)

function async_put()
	local log1 = start_end_log("async_put")
end

events.run()