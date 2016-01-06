json=require"cjson"

--read job of nodes
input_file="2506080138d1d5f991ede269fcdac9f7_host_splayd-99_5"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:", input_file)
local job,err = json.decode(l_json)
assert(job)

--read list of nodes
input_file="2506080138d1d5f991ede269fcdac9f7_host_splayd-99_5_list"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:", input_file)
local list,err = json.decode(l_json)
assert(#list.nodes==40, "Expected 40 but was: "..#list.nodes)

--read topology of nodes
input_file="2506080138d1d5f991ede269fcdac9f7_host_splayd-99_5_topology"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:",input_file)
local topo,err = json.decode(l_json)
assert(topo)
