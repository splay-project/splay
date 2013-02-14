require"splay.base"
require"distdb-client"
require"logger"

local function_list = {
	["get"] = send_get,
	["put"] = send_put,
	["del"] = send_del,
	["get_nodes"] = send_get_nodes,
	["get_keys"] = send_get_keys,
	["get_master"] = send_get_master,
	["get_all"] = send_get_all,
	["del_all"] = send_del_all,
	["set_log_lvl"] = send_set_log_lvl,
	["set_rep_params"] = send_set_rep_params,
}

local n_params = {
	["get"] = 2,
	["put"] = 4,
	["del"] = 3,
	["get_nodes"] = 0,
	["get_keys"] = 0,
	["get_master"] = 1,
	["get_all"] = 0,
	["del_all"] = 0,
	["set_log_lvl"] = 1,
	["set_rep_params"] = 3,
}

if #arg < 3 then
	print("Syntax: "..arg[0].." <ip address> <port> <function name> <args...>")
	os.exit()
end

local function_name = arg[3]

if #arg < n_params[function_name] + 3 then
	print("Insuficient arguments; function "..function_name.." requires "..n_params[function_name].." parameters")
	os.exit()
end

local ip_addr = arg[1]
local port = tonumber(arg[2])
local url = ip_addr..":"..port
print("url = "..url)

print("calling function = "..function_name)

local logfile = "<print>"
local logrules = {
	"allow *"
}
local logbatching = false
local global_details = true
local global_timestamp = false
local global_elapsed = false
init_logger(logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed)

events.run(function()
	function_list[function_name](url, arg[4], arg[5], arg[6], arg[7])
end)

