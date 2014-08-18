require"json"
f,err=io.open("/Users/veleno/workspace-git/splay/src/daemon/testcases/star_60/e451a4bc2f5a047092be27ab8761339c_host_splayd-99_5_list","r")
local l_json=f:read("*a")
f:close()
print("Input file read")
local list = json.decode(l_json)
assert(#list.nodes==20)
