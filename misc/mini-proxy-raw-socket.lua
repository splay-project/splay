local events = require"splay.events"
socket = require"socket"
require"logger"
require"distdb-client"

local ip = "127.0.0.1"
local port = 33500
local open_transactions = {}

--VARIABLES FOR LOGGING

--the path to the log file is stored in the variable logfile; to log directly on screen, logfile must be set to "<print>"
local logfile = os.getenv("HOME").."/Desktop/logfusesplay/log.txt"
--local logfile = "<print>"
--to allow all logs, there must be the rule "allow *"
local logrules = {
	"deny *",
	"deny RAW_DATA",
	"allow *"
}
local logbatching = false
local global_details = true
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
	local asked_tids = {}
	sock1:settimeout(0)
	while true do
		clt1 = sock1:accept()
		if clt1 then
			--clt1_peer_ip, clt1_peer_port = clt1:getpeername()
			command_headers = clt1:receive()
			if command_headers:sub(1, 3) == "PUT" then
				tid, url, key, consistency, value_len = command_headers:match("PUT (%d+) ([^ ]*) ([^ ]*) ([^ ]*) (%d+)")
				log1:logprint("", "PUT: transactionID="..tid..", URL="..url..", key="..key..", consistency model="..consistency..", value length="..value_len)
				value = clt1:receive(tonumber(value_len))
				log1:logprint(".RAW_DATA", "value="..value)
				open_transactions[tid] = true
				events.thread(function()
					--send_put(url, key, consistency, value, 15)
					events.sleep(3)
					open_transactions[tid] = nil
				end)
				clt1:send("YES!\n")
			else
				log1:logprint("", "It's an ASK")
				for numbers in command_headers:gmatch("%d+") do
					table.insert(asked_tids, numbers)
				end
				log1:logprint("", "ASK for open transactions: "..tbl2str("Asked TIDs", 0, asked_tids))
				local still_open = "false"
				for i,v in ipairs(asked_tids) do
					for i2,v2 in pairs(open_transactions) do
						log1:logprint("", "comparing "..v.." and "..i2)
						if v2 and v == i2 then
							log1:logprint("", "They are the same!!")
							still_open = "true"
						end
					end
				end
				clt1:send(still_open.."\n")
			end
			clt1:close()
		end
	end
end)