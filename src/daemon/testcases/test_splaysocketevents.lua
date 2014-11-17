local se =require"splay.socket_events"
assert(se.wrap)
assert(se._NAME=="splay.socket_events")

local socket=require"socket"
assert(socket)
assert(socket._VERSION=="LuaSocket 3.0-rc1")

assert(socket.bind)
local socket_wrapped_by_socket_events = se.wrap(socket)
assert(socket_wrapped_by_socket_events.bind)

local lsh = require"splay.luasocket"
local wrapped_socket = lsh.wrap(socket_wrapped_by_socket_events)
assert(wrapped_socket.bind)
