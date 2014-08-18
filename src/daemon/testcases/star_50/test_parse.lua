local cjson=require"cjson"
local json=require"json"
os=require"os"
--read raw json (list+topology)
input_file="b7cf318b9e87020a4900417a4a43b0b0a55e644b"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:", input_file)

local x = os.clock()
local list = json.decode(l_json)
print(string.format("json decoded, elapsed time: %.2f\n", os.clock() - x))

local x = os.clock()
local list,err = cjson.decode(l_json)
print(string.format("cjson decoded, elapsed time: %.2f\n", os.clock() - x))


assert(list)
assert(#list.nodes==50)
