require"json"
input_file="2506080138d1d5f991ede269fcdac9f7_host_splayd-99_5"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read")
local list,err = json.decode(l_json)
if err then
	error("Fail:", err)
end
assert(#list.nodes==20)
