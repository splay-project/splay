require"socket"
crypto = require"crypto"
require"distdb-client"

if #arg < 3 then
	print("Syntax: "..arg[0].." <URL> <size> <n_times>")
	os.exit()
end

local url = arg[1]
local size = tonumber(arg[2])
local n_times = tonumber(arg[3])
--f1 = io.open("/home/unine/rand_files/rand_10MB.txt", "r")
local f1 = io.open("test-tcp-throughput/random.dat", "r")
local data = f1:read(size)
f1:close()

local sync_modes = {"sync", "async"}
local consistency_models = {"consistent", "evtl_consistent", "paxos", "local"}
local key, time0, time1, time2, time3
local elapsed_put, elapsed_sq_put, elapsed_del, elapsed_sq_del, elapsed_get, elapsed_sq_get
local std_dev_put, std_dev_get, std_dev_del

for i1, sync_mode in ipairs(sync_modes) do
	for i2, consistency in ipairs(consistency_models) do
		for i3 = 1, 2 do
			elapsed_put = 0
			elapsed_sq_put = 0
			elapsed_get = 0
			elapsed_sq_get = 0
			elapsed_del = 0
			elapsed_sq_del = 0
			for i = 1, n_times do
				key = crypto.evp.digest("sha1", sync_mode..":"..consistency..":"..i3..":"..i)
				time0 = socket.gettime()
				send_put(url, key, sync_mode, consistency, data)
				time1 = socket.gettime()
				send_get(url, key, consistency)
				time2 = socket.gettime()
				send_del(url, key, sync_mode, consistency)
				time3 = socket.gettime()
				elapsed_put = elapsed_put + (time1 - time0)
				elapsed_sq_put = elapsed_sq_put + math.pow((time1 - time0), 2)
				elapsed_get = elapsed_get + (time2 - time1)
				elapsed_sq_get = elapsed_sq_get + math.pow((time2 - time1), 2)
				elapsed_del = elapsed_del + (time3 - time2)
				elapsed_sq_del = elapsed_sq_del + math.pow((time3 - time2), 2)
			end
			elapsed_put = elapsed_put/n_times
			std_dev_put = math.sqrt(math.abs(math.pow(elapsed_put, 2) - (elapsed_sq_put/n_times)))
			elapsed_get = elapsed_get/n_times
			std_dev_get = math.sqrt(math.abs(math.pow(elapsed_get, 2) - (elapsed_sq_get/n_times)))
			elapsed_del = elapsed_del/n_times
			std_dev_del = math.sqrt(math.abs(math.pow(elapsed_del, 2) - (elapsed_sq_del/n_times)))
			print(size.."\t"..sync_mode.."\t"..consistency.."\tPUT\t"..elapsed_put.."\t"..std_dev_put)
			print(size.."\t"..sync_mode.."\t"..consistency.."\tGET\t"..elapsed_get.."\t"..std_dev_get)
			print(size.."\t"..sync_mode.."\t"..consistency.."\tDEL\t"..elapsed_del.."\t"..std_dev_del)
		end
	end
end
