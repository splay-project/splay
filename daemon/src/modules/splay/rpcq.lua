--[[
       Splay ### v1.3 ###
       Copyright 2006-2011
       http://www.splay-project.org
]]

--[[
This file is part of Splay.

Splay is free software: you can redistribute it and/or modify 
it under the terms of the GNU General Public License as published 
by the Free Software Foundation, either version 3 of the License, 
or (at your option) any later version.

Splay is distributed in the hope that it will be useful,but 
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Splayd. If not, see <http://www.gnu.org/licenses/>.
]]

-- TODO
-- 1 connection for 2 hosts:
--	- The problem: knowing only our port, how to detect it's a local call,
--		getsockname() give something interesting on a server socket ?
--	- get who we are (port) in rpc.server()
--	- send who we are (port) when connecting to server
--	- split connect() to a common() function, too called by rpc_handler()
--	- keep "mode" in messages to distinguish reply and queries
--	- completer peer_receive() with the content of rpc_handler()
--	- if we connect ourself, call locally the function (no rpc), problem is
--		that even in a local function we need 2 sockets to communicate, but
--		peers[id] can contain only one.
--	- most of this was implemented in changeset 431: ab9c7b5f34d4
--
-- TODO send less datas

local events = require"splay.events"
local socket = require"splay.socket"
local misc = require"splay.misc"
local net = require"splay.net"
local log = require"splay.log"
local llenc = require"splay.llenc"
local enc = require"splay.benc"

local table = require"table"
local math = require"math"
local error = error
local pairs = pairs
local pcall = pcall
local print = print
local setmetatable = setmetatable
local tostring = tostring
local tonumber = tonumber
local type = type
local unpack = unpack

--module("splay.rpcq")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Remote Procedure Call Queue"
_M._VERSION     = 1.0

--[[ DEBUG ]]--
_M.l_o = log.new(3, "[splay.rpcq]")

_M.settings = {
	max = nil, -- max connections (not an hard limit)
	default_timeout = 60,
	clean_timeout = 60,
	window_size = 2,
	reconnect_interval = 5,
	nodelay = nil -- tcp nodelay option
}

_M.mode = "rpcq"

local reconnect_t, clean_t

-- The number of our messages, act as a message id, always increase
local number, count_connect, count_clean, count_lru, die = 0, 0, 0, 0, 0
local server_connect, server_close = 0, 0
-- id = "ip:port"
-- status = connected|disconnected|connecting
local peers = {}
-- message send queue for each peers
local messages = {}
-- When sent, messages are removed from 'messages' and put in 'messages_sent'
-- (max window_size messages in 'messages_sent')
-- When the message is replied, we removed it from 'messages_sent'.
-- In case of problem, messages in messages_sent are put back in messages.
local messages_sent = {}


local function num_c()
	local t_p = 0
	for _, p in pairs(peers) do
		if p.status == "connected" then t_p = t_p + 1 end
	end
	return t_p
end

function _M.stats()
	return number, misc.size(peers), num_c(), count_connect, count_clean, count_lru
end

function _M.infos()
	return "Number of RPCs: "..number.."\n"..
			"Connected peers: "..num_c().." server: "..
			(server_connect - server_close).." (different: "..misc.size(peers)..")\n"..
			"connect: "..count_connect.." clean: "..count_clean.." "..
			"clean_lru: "..count_lru.." die: "..die.." "..
			"server_connect: "..server_connect.." server_close: "..server_close
end

-- Kill the LRU connection (if a non active one !)
local function clean_lru()
	--l_o:debug("clean_lru")
	local best_last, best_id = math.huge
	for id, p in pairs(peers) do
		if p.status == "connected" and
				#messages[id] == 0 and
				#messages_sent[id] == 0 and
				p.last < best_last then

			best_last = p.last
			best_id = id
		end
	end
	if best_id then
		_M.l_o:notice("clean_lru", id)
		count_lru = count_lru + 1
		peers[best_id].s:close()
	end
end

local function clean()
	--l_o:debug("clean")
	while events.sleep(5) do
		for id, p in pairs(peers) do
			if p.status == "connected" and
					#messages[id] == 0 and
					#messages_sent[id] == 0 and
					_M.settings.clean_timeout and
					p.last < misc.time() - _M.settings.clean_timeout then
				-- => receive fail, => send fail
				_M.l_o:notice("clean", id)
				count_clean = count_clean + 1
				p.s:close()
			end
		end
	end
end

-- Cleaning after failure, or to stop connection with a peer
local function peer_fail(id)
	--l_o:debug("peer_fail", id)

	-- make the other thread fail
	peers[id].s:close()
	events.fire("rpcq:send_"..id)

	if peers[id].half then --if peers[id].half or all then
		peers[id].status = "disconnected"
		peers[id].half = nil
		if #messages_sent[id] > 0 then
			for i = #messages_sent[id], 1, -1 do
				table.insert(messages[id], 1, messages_sent[id][i])
			end
			messages_sent[id] = {}
		end
		die = die + 1
	else
		peers[id].half = true
	end
end

local function peer_receive(id)
	--l_o:debug("peer_receive", id)
	local p = peers[id]
	local s = p.s
	while true do
		local msg_s, err = s:receive()
		if not msg_s then break end
		local ok, msg = pcall(function() return enc.decode(msg_s) end)
		if not ok then
			_M.l_o:warn("peer_receive corrupted message:", msg_s)
			break
		end
		p.last = misc.time()
		table.remove(messages_sent[id], 1)
		events.fire("rpcq:reply_"..msg.n, msg.reply)
		if #messages_sent[id] < _M.settings.window_size then
			-- ready to send a new message
			events.fire("rpcq:send_"..id)
		end
	end
end

local function peer_send(id)
	--l_o:debug("peer_send "..id)
	local p = peers[id]
	local s = p.s
	while true do
		if #messages[id] == 0 or #messages_sent[id] >= _M.settings.window_size then
			--l_o:debug("peer_send wait", #messages[id], #messages_sent[id])
			events.wait("rpcq:send_"..id)
		end

		-- receive thread is dead
		if p.half then break end

		--l_o:debug("peer_send try", #messages[id], #messages_sent[id])
		if #messages[id] > 0 and #messages_sent[id] < _M.settings.window_size then
			local msg = table.remove(messages[id], 1)

			-- maybe this message is already timed-out !
			if not msg.timeout or
					(msg.timeout and msg.time >= misc.time() - msg.timeout) then
				table.insert(messages_sent[id], msg)
				p.last = misc.time()
				local dup=misc.dup(msg)
				dup.time=nil
				dup.timeout=nil
				if not s:send(enc.encode(dup)) then break end
				p.last = misc.time()
			end
		end
	end
end

-- Even if connect fail, the connection will be retried later
local function connect(id, s)
	--l_o:debug("connect", id)
	if peers[id].status == "disconnected" then
		peers[id].status = "connecting"
		local s, err = socket.tcp()
		if s then
			s = llenc.wrap(s)
			local t = misc.split(id, ":")
			local ip, port = t[1], t[2]
			local r, err = s:connect(ip, port)
			if r then

				if _M.settings.max and num_c() >= _M.settings.max then clean_lru() end

				peers[id].status = "connected"
				peers[id].s = s
				peers[id].last = misc.time()
				count_connect = count_connect + 1

				if _M.settings.nodelay then s:setoption("tcp-nodelay", true) end
				events.thread(function()
					peer_send(id)
					_M.l_o:notice("Send thread die", id)
					peer_fail(id)
				end)
				events.thread(function()
					peer_receive(id)
					_M.l_o:notice("Receive thread die", id)
					peer_fail(id)
					events.fire("rpcq:finish_"..id)
				end)
				-- Do not return until our threads are finished
				-- No need to wait for both: peer_fail() will make them finish at the same
				-- time.
				events.wait("rpcq:finish_"..id)
			else
				_M.l_o:warn("connect("..ip..":"..port.."): "..err)
				peers[id].status = "disconnected"
			end
			s:close()
		else
			_M.l_o:error("tcp(): "..err)
			peers[id].status = "disconnected"
		end
	end
end

local function expire(id)
	-- remove messages already timeouted
	if #messages[id] > 0 then
		local t = misc.time()
		local i = 1
		while true do
			if not messages[id][i] then break end
			if messages[id][i].timeout and
						messages[id][i].time < t - messages[id][i].timeout then
				table.remove(messages[id], i)
			else
				i = i + 1
			end
		end
	end
end

-- This function is only used if some peers have crashed and some messages are
-- still in the queue. If another RPC call is done to a disconnected host, the
-- host is immediatly reconnected and this reconnection not used.
local function reconnect()
	--l_o:debug("reconnect", id)
	while events.sleep(_M.settings.reconnect_interval) do
		for id, m in pairs(messages) do
			if peers[id].status == "disconnected" and
					#messages[id] > 0 then
				-- avoid reconnecting if everything is already timeouted...
				expire(id)
				if #messages[id] > 0 then
					--l_o:debug("try reconnecting", id)
					events.thread(function() connect(id) end)
				end
			end
		end
	end
end

local function init(id)
	--l_o:debug("init", id)
	if not peers[id] then
		peers[id] = {status = "disconnected", last = misc.time()}
		messages[id] = {}
		messages_sent[id] = {}
	end
end

local function rpc_handler(s)
	server_connect = server_connect + 1
	--l_o:debug("rpc_handler")
	if _M.settings.nodelay then s:setoption("tcp-nodelay", true) end
	s = llenc.wrap(s)

	while true do
		local msg_s, err = s:receive()
		if not msg_s then break end
		
		local ok, msg = pcall(function() return enc.decode(msg_s) end)
		if not ok then
			_M.l_o:warn("rpc_handler corrupted message:", msg_s)
			break
		end
        
		if msg.type == "call" then
			local c, err = misc.call(msg.call)
			if c then
				msg.reply = c
			else
				_M.l_o:warn("rpc_handler misc.call(): "..err)
			end
		elseif msg.type == "ping" then
			msg.reply = true
		end
		--these fields are not used at reception
		msg.call = nil
		msg.type = nil
		msg.time = nil
		msg.timeout = nil
		if not s:send(enc.encode(msg)) then break end
	end
	server_close = server_close + 1
	--l_o:debug("rpc_handler end")
end

function _M.server(port, max, backlog)
	return net.server(port, rpc_handler, max, nil, backlog)
end

function _M.stop_server(port)
	-- We must kill clients because rpcq is based on permanent connections,
	-- killing only the server has little effect.
	return net.stop_server(port, true)
end

-- return: true|false, array of responses
-- timeout is the max delay for the whole RPC
local function do_call(ip, port, typ, call, timeout)
	--_M.l_o:debug("do_call")
	assert(reconnect, clean)
	if not reconnect_t then reconnect_t = events.thread(reconnect) end
	if not clean_t then clean_t = events.thread(clean) end

	local id = ip..":"..port

	timeout = timeout or _M.settings.default_timeout

	number = number + 1

	local msg = {
		type = "ping",
		n = number,
		time = misc.time(),
		timeout = timeout
	}
	if typ == "call" then
		msg.type = "call"
		msg.call = call
	end

	init(id)
	table.insert(messages[id], msg)

	events.thread(function() connect(id) end)

	-- If the node is just connected, it will not receive this one, but it will
	-- anyway try to send a message immediately...
	events.fire("rpcq:send_"..id)

	local ok, reply
	if timeout then
		ok, reply = events.wait("rpcq:reply_"..msg.n, timeout) 
	else
		ok = true
		reply = events.wait("rpcq:reply_"..msg.n) 
	end
	if ok then
		return true, reply
	else
		return false, "timeout"
	end
end

--------------------[[ HIGH LEVEL FUNCTIONS ]]--------------------

-- return: true|false, array of responses
function _M.acall(ip, port, call, timeout)

	-- support for a node array with ip and port
	if type(ip) == "table" then
		if not ip.ip or not ip.port then
			_M.l_o:warn("parameter array without ip or port")
			return false, "parameter array without ip or port"
		else
			timeout = call
			call = port
			port = ip.port
			ip = ip.ip
		end
	end
	
	if timeout ~=nil and tonumber(timeout)==nil then
		_M.l_o:warn("invalid timeout value: ",timeout)
		return false, "invalid timeout value: "..timeout
	end
	
	if type(call) ~= "table" then
		call = {call}
	end

	return do_call(ip, port, "call", call, timeout)
end
-- DEPRECATED
--function a_call(...) return acall(...) end

function _M.ecall(ip, port, func, timeout)
	local ok, r = _M.acall(ip, port, func, timeout)
	if ok then
		return unpack(r)
	else
		error(r)
	end
end

-- To be used when we are sure that all the rpc reply return something other
-- than nil, then nil will indicate and error. The best way to do is to use
-- acall() and then unpack the second return values or use it as an array.
function _M.call(ip, port, func, timeout)
	--_M.l_o:debug("call",ip,port,func,timeout)
	local ok, r = _M.acall(ip, port, func, timeout)
	if ok then
		return unpack(r)
	else
		return nil, r
	end
end

-- RPC ping
function _M.ping(ip, port, timeout)
	-- support for a node array with ip and port
	if type(ip) == "table" and ip.ip and ip.port then
		timeout = port
		port = ip.port
		ip = ip.ip
	end
	local t = misc.time()
	local ok, r = do_call(ip, port, "ping", nil, timeout)
	if ok then
		return misc.time() - t
	else
		return nil, r
	end
end

--[[ Create an RPC proxy object

You can then call functions on that object with the classical notation:

o = rpc.proxy(node)
o:remote_function(arg1, arg2)
]]
function _M.proxy(ip, port)
	local p = {}
	if type(ip) == "table" then
		p.port = ip.port
		p.ip = ip.ip
	else
		p.port = port
		p.ip = ip
	end
	
	p.timeout = _M.settings.default_timeout
	p.ping = function(self)
		return ping(self, self.timeout)
	end

	setmetatable(p,
		{__index = function(t, func) 
			-- if __index is called, timeout == nil
			if func == "timeout" then return nil end
			return function(self, ...)
				return ecall(self, {func, unpack(arg)}, self.timeout)
			end
		end})
	return p
end

return _M