local dbclient = require 'distdb-client'

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

for 