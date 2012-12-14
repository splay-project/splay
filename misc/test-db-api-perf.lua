local misc = require"splay.misc"
local dbclient = require 'distdb-client'
local crypto = require"crypto"

local block_size = tonumber(arg[1])
local n_times = tonumber(arg[2])
local consistency_model = arg[3]
local url = arg[4]


if (#arg < 5) or (type(n_times) ~= "number") or (type(block_size) ~= "number") then
	print()
	print ("Syntax: lua test-db-api-perf.lua <block_size> <n_times> <consistency_model> <url>")
	print()
	print ("\tconsistency-model: \"consistent\", \"evtl_consistent\" \"paxos\"")
	print ("\tblock_size is in kB (1024 B)")
	print ("\turl is \"A.B.C.D:port\"")
	print()
	print ("Example: lua test-db-api-perf.lua 64 100 consistent 127.0.0.1:20000")
	print()
	os.exit()
end

local value1 = nil
local value2 = nil
local ok_get = nil
local start_time = nil
local time_put = 0

local function gen_rand_string(size)
	local tbl1 = {}
	for i=1,size*1024 do
		tbl1[i] = string.char(math.random(256)-1)
	end
	return table.concat(tbl1)
end

for i=1,n_times do
	key = crypto.evp.digest("sha1", "unhashed_key"..i)
	value1 = gen_rand_string(block_size)
	start_time = misc.time()
	send_put(url, key, consistency_model, value1)
	time_put = time_put + misc.time() - start_time
	ok_get, value2 = send_get(url, key, consistency_model)
	if value1 ~= value2 then
		print("FATAL ERROR, PUT/GET CORRUPTED")
		os.exit()
	end
	send_delete(url, key, consistency_model)
	print("Test nº "..i.." performed")
end
print("PUT time = "..(time_put/n_times))