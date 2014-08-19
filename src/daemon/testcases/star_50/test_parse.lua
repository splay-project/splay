local cjson=require"cjson"
local json=require"json"
os=require"os"
--read raw json (list+topology)
input_file="raw.json"
f,err=io.open(input_file,"r")
local l_json=f:read("*a")
f:close()
print("Input file read:", input_file)

local x = os.clock()
local list = json.decode(l_json)
print(string.format("json decoded, elapsed time: %.2f\n", os.clock() - x))
assert(#list.nodes==50)

local x = os.clock()
local list = cjson.decode(l_json)
print(string.format("cjson decoded, elapsed time: %.2f\n", os.clock() - x))


assert(list)
assert(#list.nodes==50)

local x = os.clock()
local jlist = json.encode(list)
print(string.format("json encoded, elapsed time: %.2f\n", os.clock() - x))
print("json, length of string: ",#jlist)
local x = os.clock()
local jlist,err = cjson.encode(list)
print(string.format("cjson encoded, elapsed time: %.2f\n", os.clock() - x))
print("cjson, length of string: ",#jlist)


