require"json"
--read raw json (list+topology)
input_file="raw.json"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:", input_file)
local list,err = json.decode(l_json)
assert(list)
assert(#list.nodes==50)
