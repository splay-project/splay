--for raw socket communication
socket = require"socket"

if #arg < 3 then
	print("TCP Throughput Test: Usage: "..arg[0].." <server port> <payload size> <number of times>")
	os.exit()
end

local ip = "0.0.0.0"
local port = tonumber(arg[1])
local clt1 = nil
local size = tonumber(arg[2])
local n_times = tonumber(arg[3])

print("Listening on port "..port)

--opens a new socket
local sock1 = socket.tcp()
--binds the socket (server mode)
sock1:bind(ip, port)
--listens (waits for client connections)
sock1:listen()
--repeat n_times
for i = 1, n_times do--accept incoming connections
	clt1 = sock1:accept()
	--receives a line of text from the client (a string ending with "\n" - the "\n" is pruned automatically)
	rec_str = clt1:receive(size)
	--answers "OK" to the FlexiFS client
	clt1:send("OK")
	--closes the client socket
	clt1:close()
end
--closes the server socket
sock1:close()
