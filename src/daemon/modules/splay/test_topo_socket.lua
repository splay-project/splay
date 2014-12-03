--setup double wrapping, topo and rs

log=require"splay.log"
l_o=log.new(3,"[test_topo_socket]")
socket = require"socket.core"
l_o:print("Socket type:",socket)

ts = require"splay.topo_socket"
ts.l_o.level=3
assert(ts.init({in_delay=1})) --seconds
socket=ts.wrap(socket)
l_o:print("Socket type:",socket)

rs=require"splay.restricted_socket"
rs.l_o.level=3
assert(rs.init({max_sockets=1024}))
socket=rs.wrap(socket) --to gather stats on network IO and simulate in-controller deploy
l_o:print("Socket type:",socket)

require"splay.base"

events=require"splay.events"
rpc=require"splay.rpc"
rpc.l_o.level=1

events.run(function()

	rpc.server({ip="127.0.0.1",port=10002})
	for i=1,10 do
		local rtt,err=rpc.ping({ip="127.0.0.1",port=10002},12) 
		l_o:print(rtt,err)
		--events.sleep(0.5)
	end
	rpc.stop_server(10002)
	events.exit()
end)
