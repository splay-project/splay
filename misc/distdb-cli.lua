require "splay.base"
local distdb_clt = require "distdb-client"

local ip_addr = arg[1]
local port = tonumber(arg[2])
local url = ip_addr..":"..port

print("url = "..url)

local function_list = {
	["send_get"] = send_get,
	["send_put"] = send_put,
	["send_delete"] = send_delete,
	["send_get_node_list"] = send_get_node_list,
	["send_get_key_list"] = send_get_key_list,
	["send_get_master"] = send_get_master,
	["send_get_all_records"] = send_get_all_records,
	["send_change_log_lvl"] = send_change_log_lvl
}

local function_name = arg[3]

print("calling function = "..function_name)

events.run(function()
	function_list[function_name](url, arg[4], arg[5], arg[6])
end)

