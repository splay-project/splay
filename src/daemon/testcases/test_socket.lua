local socket = require"socket"
assert(socket._VERSION ==	"LuaSocket 3.0-rc1")
assert(socket.dns) --	table: 0x7fc8b1c0fc60
assert(socket._SETSIZE==	1024)
assert(socket.protect) --	function: 0x105c0bff0
assert(socket.choose) --	function: 0x7fc8b1c06310
assert(socket.try) --	function: 0x7fc8b1c062e0
assert(socket.connect4) --	function: 0x7fc8b1c0fa50
assert(socket.udp6) --	function: 0x105c0d620
assert(socket.tcp6) --	function: 0x105c0cd30
assert(socket.source) --	function: 0x7fc8b1c0ac40
assert(socket.skip) --	function: 0x105c08520
assert(socket.bind) --	function: 0x7fc8b1c06280
assert(socket.newtry) --	function: 0x105c0c010
assert(socket.BLOCKSIZE==	2048)
assert(socket.sleep) --	function: 0x105c08680
assert(socket.sinkt) --	table: 0x7fc8b1c0dd60
assert(socket.udp) --	function: 0x105c0d630
assert(socket.sourcet) --	table: 0x7fc8b1c0dd20
assert(socket.connect6) --	function: 0x7fc8b1c0fab0
assert(socket.connect) --	function: 0x105c0c990
assert(socket.tcp) --	function: 0x105c0cd40
assert(socket.__unload) --	function: 0x105c08510
assert(socket.select) --	function: 0x105c0c580
assert(socket.gettime) --	function: 0x105c087a0
assert(socket.sink) --	function: 0x7fc8b1c0ddd0
print("Test OK")
--for k,v in pairs(socket) do
--	print(k,v)
--end