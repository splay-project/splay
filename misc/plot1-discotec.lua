require"socket"
local crypto = require"crypto"

if #arg < 3 then
	print("Syntax: "..arg[0].." <URL> <input_file> <n_times>")
	os.exit()
end

local url = arg[1]
local input_file = arg[2]
local n_times = tonumber(arg[3])

local f1 = io.open(input_file, "r")
local data = f1:read("*a")

print("Data Size = "..data:len())

os.exit()

f_tbl = {
	[1] = function(data)
		send_put()
	end,
	[2] = function(data)
		send_put()
	end,
	[3] = function(data)
		send_put()
	end,
	[4] = function(data)
		send_put()
	end,
	[5] = function(data)
		send_put()
	end,
	[6] = function(data)
		send_put()
	end
}

local key = nil

for 
	for i = 1, n_times do
		key = 
	end
	for i = 1, n_times do

		start_time = socket.gettime()
		elapsed = elapsed + socket.gettime() - start_time
		elapsed_sq = elapsed + math.pow(socket.gettime() - start_time), 2)
	end
end


--registers the starting time in seconds (with .4 digit precision)
		
		--makes the rpc call
		rpc.call(server_addr, {"recv_data", payload})
		--registers 2nd timestamp
		time1 = time1 + socket.gettime() - time0
	end
	time1 = time1/n_times
	print("Time 1 = "..time1)