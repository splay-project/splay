local events = require"splay.events"
socket = require"socket"
require"logger"
require"distdb-client"

local ip = "127.0.0.1"
local port = 33500

--VARIABLES FOR LOGGING

--the path to the log file is stored in the variable logfile; to log directly on screen, logfile must be set to "<print>"
--local logfile = os.getenv("HOME").."/Desktop/logfusesplay/log.txt"
local logfile = "<print>"
--to allow all logs, there must be the rule "allow *"
local logrules = {
	"deny RAW_DATA",
	"allow *"
}
local logbatching = false
local global_details = false
local global_timestamp = false
local global_elapsed = false

init_logger(logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed)

--MAIN
events.run(function()
	local log1 = start_logger("MAIN", "Starting Mini Proxy (Raw Socket), IP address="..ip..", port="..port)

	local sock1 = socket.tcp()
	sock1:bind(ip, port)
	sock1:listen()
	local clt1, clt1_peer_ip, clt1_peer_port, command_headers, tid, url, key, consistency, value_len, value

	while true do
		clt1 = sock1:accept()
		--clt1_peer_ip, clt1_peer_port = clt1:getpeername()
		command_headers = clt1:receive()
		tid, url, key, consistency, value_len = command_headers:match("(%d+) ([^ ]*) ([^ ]*) ([^ ]*) (%d+)")
		log1:logprint("", "Received from "..clt1_peer_ip..":"..clt1_peer_port.." = \""..command_headers.."\"")
		log1:logprint("", "transactionID="..tid..", URL="..url..", key="..key..", consistency model="..consistency..", value length="..value_len)
		--TODO convert tid to number
		value = clt1:receive(tonumber(value_len))
		log1:logprint(".RAW_DATA", "value="..value)
		clt1:close()
		send_put(url, key, consistency, value)
	end
end)