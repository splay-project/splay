require"socket"
rpc = require"splay.rpc"
events = require"splay.events"

if #arg < 4 then
	print("TCP Throughput Test: Usage: "..arg[0].." <server IP> <server port> <payload size> <number of times>")
	os.exit()
end

local server_addr = {ip=arg[1], port=tonumber(arg[2])}
local size = tonumber(arg[3])
local n_times = tonumber(arg[4])

--opens the file with random data
local f1 = io.open("../random.dat", "r")
--reads the file and fills the payload
local payload = f1:read(size)
--closes the file
f1:close()
local time0 = 0
local time1 = 0
events.run(function()
	--repeat n_times
	for i = 1, n_times do
		--registers the starting time in seconds (with .4 digit precision)
		time0 = socket.gettime()
		--makes the rpc call
		rpc.call(server_addr, {"recv_data", payload})
		--registers 2nd timestamp
		time1 = time1 + socket.gettime() - time0
	end
	time1 = time1/n_times
	print("Time 1 = "..time1)
end)
