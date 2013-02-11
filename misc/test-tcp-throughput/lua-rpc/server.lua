require"splay.base"
rpc = require"splay.rpc"

if #arg < 1 then
	print("TCP Throughput Test: Usage: "..arg[0].." <server port>")
	os.exit()
end

local port = tonumber(arg[1])

print("Listening on port "..port)

function recv_data(data)
	return "OK"
end

--starts the server
rpc.server(port)
--main loop
events.run()
