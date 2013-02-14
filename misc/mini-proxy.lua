--the prosody libraries where taken from Prosody (http://www.prosody.im); used for HTTP asynchronous clients
local http = require"prosody.http"
local server = require"prosody.server"
--logger provides some fine tunable logging functions
require"logger"
--for raw socket communication
socket = require"socket"

local ip = "127.0.0.1"
local port = 33500
local open_transactions = {}

--VARIABLES FOR LOGGING

--the path to the log file is stored in the variable logfile; to log directly on screen, logfile must be set to "<print>"
--local logfile = os.getenv("HOME").."/logflexifs/log.txt"
local logfile = "<print>"
--to allow all logs, there must be the rule "allow *"
local logrules = {
	"deny COMPARE",
	"deny RAW_DATA",
	--"deny PROSODY_MODULE",
	"allow *"
}
local logbatching = false
local global_details = true
local global_timestamp = false
local global_elapsed = false

init_logger(logfile, logrules, logbatching, global_details, global_timestamp, global_elapsed)

--function send_command_cb: callback function for send_command (gets executed when the HTTP request is answered)
local function send_command_cb(response, code, request)
	--starts the logger
	--local log1 = start_logger(".DB_OP send_command_cb", "INPUT", "response="..response..", code="..tostring(code)..", request="..type(request))
	local log1 = start_logger(".DB_OP send_command_cb")
	
	--[[
	--TODO: check if the response is a 200, and the DB response is positive
	CODE FROM send_command IN distdb_client

	--if the response is not a 200 OK
	if response_status ~= 200 then
		--logs the error
		log1:logprint("END ERROR", "response_status="..response_status)
		--flushes all logs
		log1:logflush()
		--returns false and the error
		return false, response_status
	end

	--if it arrives here, it means it didn't enter inside the if
	log1:logprint("", "200 OK received")
	--logs END of the function and flushes all logs
	log1:logprint("END", "", "result_mode="..tostring(result_mode))
	--if there is a response_body
	if type(response_body) == "table" and response_body[1] then
		--returns true (indicates a succesful call), and the return value
		return true, serializer.decode(response_body[1])
	end
	--if there was no response body, returns only "true"
	--]]

	if request.piggyback then
		log1:logprint(".TABLE", "Shutting down "..request.piggyback_tid)
		log1:logprint(".ADD_DEL_TIDS", "Shutting down "..request.piggyback_tid)
		open_transactions[request.piggyback_tid] = nil
	end
end

--function send_put: sends a PUT command to the Entry Point
function send_command(tid, command_name, url, consistency, value, value_len)
	--starts the logger
	local log1 = start_logger(".DB_OP send_command", "INPUT", "TID="..tid..", command_name="..command_name..", URL="..url..", consistency="..consistency..", value length="..(value_len or 0))
	--logs more input
	log1:logprint(".RAW_DATA INPUT", "value="..(value or "nil"))
	--defines the options:
	local options = {
		--Headers: content length is the size in bytes of the value to be put, content type is plain text, and "Type" holds the consistency model
		headers = {
			["Content-Length"] = value_len,
			["Content-Type"] =  "plain/text",
			["No-Ack"] = "false",
			["Type"] = consistency
		},
		--the body contains the value to be put
		body = tostring(value),
		--the method is the command name (trailing space required by the prosody libs)
		method = command_name.." "
	}
	--makes the HTTP request
	local req = http.request(url, options, send_command_cb)
	--stamps the TID as a piggyback on the request (to be used by send_command_cb)
	req.piggyback_tid = tid
	--logs end
	log1:logprint_flush("END")
end

--START MAIN ROUTINE

--initializes variables
local msg, clt1, clt1_peer_ip, rec_str, command_name, tid, url, key, consistency, value_len, value, asked_tids, still_open
--starts log
local log1 = start_logger("MAIN", "Starting Mini Proxy (Raw Socket), IP address="..ip..", port="..port)
--opens a new socket
local sock1 = socket.tcp()
--binds the socket (server mode)
sock1:bind(ip, port)
--listens (waits for client connections)
sock1:listen()
--sets the accept timeout as 0 (non-blocking)
sock1:settimeout(0)

--main loop (alternates socket_accept -facing FlexiFS Client- and server.loop -facing FlexiFS DB)
repeat
	--accept incoming connections
	clt1 = sock1:accept()
	--if there is a client connected
	if clt1 then
		--receives a line of text from the client (a string ending with "\n" - the "\n" is pruned automatically)
		rec_str = clt1:receive()
		--if the first three bytes are "PUT" it is a PUT command
		if rec_str:sub(1, 3) == "PUT" or rec_str:sub(1, 3) == "DEL" then
			--parses the the received string
			command_name, tid, url, key, consistency, value_len = rec_str:match("([^ ]*) (%d+) ([^ ]*) ([^ ]*) ([^ ]*) (%d+)")
			--logs
			log1:logprint("", command_name..": transactionID="..tid..", URL="..url..", key="..key..", consistency model="..consistency..", value length="..value_len)
			--if the command is a PUT
			if command_name == "PUT" then
				--retrieves the value to be written, according to the value length received in the previous line
				value = clt1:receive(tonumber(value_len))
			end
			--logs
			log1:logprint(".RAW_DATA", "value="..value)
			--registers the transaction
			open_transactions[tid] = true
			--answers "OK" to the FlexiFS client
			clt1:send("OK\n")
			--sends the command to the DB
			send_command(tid, command_name, "http://"..url.."/"..(key or ""), consistency, value, value_len)
		--if not, it is an ASK command
		else
			--initializes the table of "Asked TIDs" (the TIDs whose status is being asked)
			asked_tids = {}
			--parses the received string; TIDs are under the format: "TID1 TID2 TID3" (numbers separated by one space)
			for numbers in rec_str:gmatch("%d+") do
				--fills the table of Asked TIDs
				table.insert(asked_tids, numbers)
			end
			--logs the table of open transactions and the table of Asked TIDs
			log1:logprint(".COMPARE", tbl2str("Open Transactions", 0, open_transactions))
			log1:logprint(".COMPARE", "ASK for open transactions: "..tbl2str("Asked TIDs", 0, asked_tids))
			--initializes still_open as "false"
			still_open = "false"
			--for all asked TIDs
			for i,v in ipairs(asked_tids) do
				--and for all open transactions
				for i2,v2 in pairs(open_transactions) do
					--compares; if they are the same (it means that the asked TIDs is in the list of open transactions)
					if v == i2 then
						--logs
						log1:logprint(".COMPARE", v.." and "..i2.." are the same!!")
						--still_open is true. TODO: this can be improved; we need to break the two loops
						still_open = "true"
					end
				end
			end
			--sends the answer
			clt1:send(still_open.."\n")
		end
		--closes the client socket
		clt1:close()
	end
	--performs the server loop (needed for the Prosody's ansychronous HTTP clients)
	msg = server.loop(true)
--until the server sends "quitting" (not sure when that happens... i quit with Ctrl+C)
until msg == "quitting"