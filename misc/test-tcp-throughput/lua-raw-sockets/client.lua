local socket = require"socket"

if #arg < 4 then
	print("TCP Throughput Test: Usage: "..arg[0].." <server IP> <server port> <payload size> <number of times>")
	os.exit()
end

local server_ip = arg[1]
local server_port = tonumber(arg[2])
local sock1 = nil
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
local time2 = 0
local time3 = 0
local time4 = 0
--repeat n_times
for i = 1, n_times do
	--opens a new socket
	sock1 = socket.tcp()
	--registers the starting time in seconds (with .4 digit precision)
	time0 = socket.gettime()
	--tries to connect to the mini proxy
	sock1:connect(server_ip, server_port)
	--registers 2nd timestamp
	time1 = time1 + socket.gettime() - time0
	--send the PUT command through raw TCP
	sock1:send(payload)
	--registers 3th timestamp
	time2 = time2 + socket.gettime() - time0
	--waits for the answer
	answer = sock1:receive(2)
	--registers 4th timestamp
	time3 = time3 + socket.gettime() - time0
	--closes the socket
	sock1:close()
	--takes 5th timestamp
	time4 = time4 + socket.gettime() - time0
end

time1 = time1/n_times
time2 = time2/n_times
time3 = time3/n_times
time4 = time4/n_times

print("Time 1 = "..time1)
print("Time 2 = "..time2)
print("Time 3 = "..time3)
print("Time 4 = "..time4)
