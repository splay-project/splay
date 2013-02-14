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
		send_put(url, key, nil, "consistent", data)
	end,
	[2] = function()
		send_put(url, key, nil, "evtl_consistent", data)
	end,
	[3] = function()
		send_put(url, key, nil, "local", data)
	end,
	[4] = function()
		send_put(url, key, nil, "paxos", data)
	end,
	[5] = function()
		send_async_put(tid, url, key, "consistent", data)
	end,
	[6] = function()
		send_put(url, key, "true", "local", data)
	end,
}

key = nil
start_time = nil
end_time = nil

modes = {1, 2, 3, 4, 5, 6}

f1 = io.open("log-plot1.txt", "w")

key = crypto.evp.digest("sha1", "default")

mode_names = {"SC", "EC", "LOC", "LIN", "ASYNC_SC", "NOACK_LOC"}

for _, mode in pairs(modes) do
		elapsed = 0
		elapsed_sq = 0
		io.write(mode_names[mode]..":\t")
		f1:write(mode_names[mode]..":\n")
		for i = 1, n_times do
			start_time = socket.gettime()
			f_tbl[mode]()
			end_time = socket.gettime()
			elapsed = elapsed + (end_time - start_time)
			elapsed_sq = elapsed_sq + math.pow((end_time - start_time), 2)
			f1:write(i.."th: elapsed time = "..(end_time - start_time).."\n")
			f1:flush()
		end
		elapsed = elapsed/n_times
		io.write("Average elapsed time = "..elapsed.."\t")
		f1:write("Average elapsed time = "..elapsed.."\n")
		elapsed_sq = elapsed_sq/n_times
		std_dev = math.sqrt(math.abs(math.pow(elapsed, 2) - elapsed_sq))
		print("Standard Dev  = "..std_dev)
		f1:write("Standard Dev  = "..std_dev.."\n")
		--we dispose the first n_times experiments, but i'm interested in seeing the results anyway
		elapsed = 0
		elapsed_sq = 0
		for i = 1, n_times do
			start_time = socket.gettime()
			f_tbl[mode]()
			end_time = socket.gettime()
			elapsed = elapsed + (end_time - start_time)
			elapsed_sq = elapsed_sq + math.pow((end_time - start_time), 2)
			f1:write((n_times + i).."th: elapsed time = "..(end_time - start_time).."\n")
			f1:flush()
		end
		elapsed = elapsed/n_times
		io.write("Average elapsed time = "..elapsed.."\t")
		f1:write("Average elapsed time = "..elapsed.."\n")
		elapsed_sq = elapsed_sq/n_times
		std_dev = math.sqrt(math.abs(math.pow(elapsed, 2) - elapsed_sq))
		print("Standard Dev  = "..std_dev)
		f1:write("Standard Dev  = "..std_dev.."\n")
end
f1:close()
