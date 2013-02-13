require"socket"
crypto = require"crypto"
logger = require"logger"
require"distdb-client"

if #arg < 3 then
	print("Syntax: "..arg[0].." <URL> <size> <n_times>")
	os.exit()
end

--the path to the log file is stored in the variable logfile; to log directly on screen, logfile must be set to "<print>"
logfile = "<print>"
--to allow all logs, there must be the rule "allow *"
logrules = {
}
--if logbatching is set to true, log printing is performed only when explicitely running logflush()
logbatching = false
global_details = true
global_timestamp = false
global_elapsed = false
init_logger(logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed)

tid = 1
url = arg[1]
size = tonumber(arg[2])
n_times = tonumber(arg[3])
--f1 = io.open("/home/unine/rand_files/rand_10MB.txt", "r")
f1 = io.open("test-tcp-throughput/random.dat", "r")
data = f1:read(size)
f1:close()

f_tbl = {
	[1] = function()
		send_put(url, key, "consistent", data)
	end,
	[2] = function()
		send_put(url, key, "evtl_consistent", data)
	end,
	[3] = function()
		send_put(url, key, "paxos", data)
	end,
	[4] = function()
		async_send_put(tid, url, key, "consistent", data)
	end,
	[5] = function()
		async_send_put(tid, url, key, "evtl_consistent", data)
	end,
	[6] = function()
		async_send_put(tid, url, key, "paxos", data)
	end,
	[7] = function()
		send_del(url, key, "consistent")
	end,
	[8] = function()
		send_del(url, key, "evtl_consistent")
	end,
	[9] = function()
		send_del(url, key, "paxos")
	end,
}

key = nil
start_time = nil
end_time = nil

modes = {1, 2, 3, 4, 5, 6}

for _, mode in pairs(modes) do
	elapsed = 0
 	elapsed_sq = 0
	for i = 1, n_times do
		key = crypto.evp.digest("sha1", mode..":"..i)
		if (i%100) == 0 then
			print(os.time(), "1:", i, mode)
		end
		f_tbl[mode]()
		--os.execute("sleep 0.5")
		f_tbl[7 + ((mode-1)%3)]()
		--os.execute("sleep 0.5")
	end
	for i = 1, n_times do
		key = crypto.evp.digest("sha1", mode..":"..(2*i))
		if (i%100) == 0 then
			print(os.time(), "2:", i, mode)
		end
		start_time = socket.gettime()
		f_tbl[mode]()
		end_time = socket.gettime()
		elapsed = elapsed + (end_time - start_time)
		elapsed_sq = elapsed_sq + math.pow((end_time - start_time), 2)
		--os.execute("sleep 0.5")
		f_tbl[7 + ((mode-1)%3)]()
		--os.execute("sleep 0.5")
	end
	elapsed = elapsed/n_times
	print("Average elapsed time = "..elapsed)
	elapsed_sq = elapsed_sq/n_times
	std_dev = math.sqrt(math.abs(math.pow(elapsed, 2) - elapsed_sq))
	print("Standard Dev  = "..std_dev)
end
