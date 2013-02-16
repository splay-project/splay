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
local elapsed = 0
local elapsed_sq = 0
local start_time, end_time, std_dev
events.run(function()
	--repeat n_times
	elapsed = 0
	elapsed_sq = 0
	io.write("Size="..size..":\t")
	for i = 1, n_times do
		start_time = socket.gettime()
		rpc.call(server_addr, {"recv_data", payload})
		end_time = socket.gettime()
		elapsed = elapsed + (end_time - start_time)
		elapsed_sq = elapsed_sq + math.pow((end_time - start_time), 2)
	end
	elapsed = elapsed/n_times
	io.write("Average elapsed time = "..elapsed.."\t")
	elapsed_sq = elapsed_sq/n_times
	std_dev = math.sqrt(math.abs(math.pow(elapsed, 2) - elapsed_sq))
	print("Standard Dev  = "..std_dev)
	--we dispose the first n_times experiments, but i'm interested in seeing the results anyway
	elapsed = 0
	elapsed_sq = 0
	for i = 1, n_times do
		start_time = socket.gettime()
		rpc.call(server_addr, {"recv_data", payload})
		end_time = socket.gettime()
		elapsed = elapsed + (end_time - start_time)
		elapsed_sq = elapsed_sq + math.pow((end_time - start_time), 2)
	end
	elapsed = elapsed/n_times
	io.write("Average elapsed time = "..elapsed.."\t")
	elapsed_sq = elapsed_sq/n_times
	std_dev = math.sqrt(math.abs(math.pow(elapsed, 2) - elapsed_sq))
	print("Standard Dev  = "..std_dev)
end)
