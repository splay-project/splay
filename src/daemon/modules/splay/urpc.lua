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

--[[

UDP based RPC
-------------

Pros:
	- Faster than TCP
	- Only one socket used, both for receiving and sending

Cons:
	- Limited size of RPC (8k)
	- Limited fault tolerance (we include a timeout and retry system)

- Adaptative retry
- Response caching
- Host to IP resolution
- Detect and report call size problem (max 8k)

DATAGRAM
--------

	=>
	key (~ 30 octets)
	type = call || ping
	[call] = array with function call
	[source_ip]
	[source_port]

	<=
	reply
	key
	type = call || ping
	[call] = array with function call results
	[error] = size error...

	(try to free memory before timeout, 1 more packet but less CPU computation)
	=>
	free
	key

NOTE:

First, we set a default socket that will permit us to send RPC (and receive
the replies). This default server will always run once with have done an RPC
call (but no one will use it to contact us since it is on a random unknown
port). Then, calling server(port), we will setup an additionnal server, on a
specific port this time. The default socket, will still be used to send and
receive RPC done by this host.

setsockname must be called (in server()) before sending any UDP messages.
If not, a free port will be taken and it will not be possible to bind it
anymore on the choosen port (or use 2 socket).

When re-sending an UDP RPC, we will keep the same key. The server will cache
the response it send for a key the first time and reuse that value. Old reply
values will be cleaned. That way, we avoid calling again a function.

Once we have received the reply, we will fire en event with the reply key: or
is the first reply and the function is still waiting for it, or this is not
the first and nobody wait for that event.

The fact that we run a local server if no server is defined, will generate a
warning "receivefrom(): nil refused" when we launch another local server
because the previous socket waiting is closed.
]]

local math = require"math"
local string = require"string"
local crypto = require"crypto"
local events = require"splay.events"
local socket = require"splay.socket"
--local enc = require"json"
local enc = require"splay.benc"
local misc = require"splay.misc"
local log = require"splay.log"

local error = error
local pairs = pairs
local pcall = pcall
local print = print
local setmetatable = setmetatable
local tostring = tostring
local type = type
local unpack = unpack
local tonumber = tonumber

--module("splay.urpc")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "UDP RPC"
_M._VERSION     = 1.0
_M._NAME = "splay.urpc"
--[[ DEBUG ]]--
_M.l_o = log.new(3, "[".._M._NAME.."]")

_M.settings = {
	max = nil, -- max outgoing RPCs
	default_timeout = 40,
	retry_number = 2,
	cleaning_after = 120, -- max timeout = 0.9 * cleaning_after
	cleaning_interval = 5,
	try_free = true -- send an aditional message to free the cache
}

_M.mode = "urpc"

local number = 0
local call_s = nil

local sockets = {}

local replied = {} -- store reply and their values (server)
local messages = {} -- messages to send or resend (still not replied)
local server_run = false
local server_port = nil --assigned when unconnected->connected
local base_key = nil
local c = 0
function _M.get_key(seed)
	if not base_key then
		base_key = crypto.evp.new("sha1"):digest(math.random()..tostring(seed))
	end
	c = c + 1
	return base_key..c
end

function _M.stats()
	return number
end

function _M.infos()
	return "Number of RPCs: "..number
end

local function clean_replied()
	local now = misc.time()
	for key, d in pairs(replied) do
		-- If we clean the entry too soon, we will maybe still receive a msg for
		-- that function call. If the entry is cleaned, we need to call the
		-- function again, that in most cases is not wanted.
		if _M.settings.cleaning_after and d.time + _M.settings.cleaning_after < now then
			--l_o:debug("CLEANING", key)
			replied[key] = nil
		end
	end
end

-- server function
local function reply(s, data, ip, port)

	local reply_s

	-- could permit a special routing, normally data.source_* is not set
	if data.source_ip and data.source_port then
		ip, port = data.source_ip, data.source_port
		data.source_ip, data.source_port = nil, nil
	end

	data.reply = true
	-- For type "ping", nothing more to do
	if data.type == "call" then
		if not replied[data.key] then
			--l_o:debug("call()", data.key)
			local val = misc.call(data.call)
			-- TODO good error report
			if val == nil then val = {nil} end
			replied[data.key] = {val = val, time = misc.time()}
		end

		data.call = replied[data.key].val
		reply_s = enc.encode(data)
		local length = #reply_s
		if length > 8192 then
			data.call = nil
			data.error = "reply length ("..length..")"
			-- we were optimistic, we need to reencode now...
			reply_s = enc.encode(data)
			_M.l_o:warning("reply(): too much data")
		end
	else
		reply_s = enc.encode(data)
	end

	local ok, err = s:sendto(reply_s, ip, port)
	if not ok then
		_M.l_o:warn("sendto(): "..err)
	end
end

local function process_one_msg(s, data, ip, port)
	local ok, data = pcall(function() return enc.decode(data) end)
	if ok then
		if data.reply then -- we have received a reply
			messages[data.key] = nil
			if _M.settings.try_free then
				s:sendto(enc.encode({free = true, key = data.key}), ip, port)
			end
			return events.fire("urpc:"..data.key, data)
		elseif data.free then -- we have received a free packet
			replied[data.key] = nil
		else
			return reply(s, data, ip, port)
		end
	else
		_M.l_o:warn("corrupted message")
	end
end

--[[ Thread that will send or resend RPC ]]--
local function sender(s)
	while true do

		--_M.l_o:debug("sender() loop")
		local q = {}
		local now, next_wakeup = misc.time()

		for key, data in pairs(messages) do
			if data.next_try <= now then
			
				--_M.l_o:debug("try", data.nb_try, data.key)

				-- add to the send queue
				q[#q + 1] = misc.dup(data)

				data.nb_try = data.nb_try + 1
				data.next_try = now + (data.timeout / (_M.settings.retry_number + 1))

				if data.nb_try >= _M.settings.retry_number then
					messages[key] = nil
				else
					if not next_wakeup or data.next_try < next_wakeup then
						next_wakeup = data.next_try
					end
				end
			else
				if not next_wakeup or data.next_try < next_wakeup then
					next_wakeup = data.next_try
				end
			end
		end

		if #q > 0 then
			for _, data in pairs(q) do
				-- sending
				s:sendto(data.enc, data.ip, data.port)
				-- unconnected->connected
				local ip,port = s:getsockname()
				server_port=port
				sockets[server_port]=s -- to be able to close it later
			end
			q = {}
		end

		if next_wakeup then
			--_M.l_o:debug("wait", next_wakeup - now)
			events.wait("urpc:sender", next_wakeup - now)
		else
			--_M.l_o:debug("wait")
			events.wait("urpc:sender")
		end
	end
end

local function receiver(s)
	while true do
		local data, ip, port = s:receivefrom()
		if data then
			events.thread(function()
				process_one_msg(s, data, ip, port)
			end)
		else
			if ip == "timeout" then
				_M.l_o:warn("receivefrom(): "..ip)
			else
				_M.l_o:notice("receivefrom(): server closed")
				break
			end
		end
	end
end

-- To enable an additional RPC server on a specific port
function _M.server(port)
	local ip="*" --bind on all IPs on this machine
	if type(port) == 'table' and port.port then
		if port.ip then ip=port.ip end
		port = port.port
	end
	
	--verify conflicts with default_server's port
	local default_to_restart=false	
	if  port==server_port then
		server_run=false
		default_to_restart=true
		sockets[server_port]:close()
		sockets[server_port]=nil
	end
	
	local s, err = socket.udp()
	if not s then
		_M.l_o:warn("udp():"..err)
		return nil, err
	end

	_M.l_o:notice("URPC server bound on port "..port)
	
	local r, err = s:setsockname(ip, port)
	
	if not r then
		_M.l_o:warn("setsockname("..port.."): "..err)
		return nil, err
	end

	sockets[port] = s -- to be able to close it later
	events.thread(function() receiver(s) end)
	
	--if the default server was stopped due to port conflict, restart it
	if default_to_restart then _M.default_server() end
	
	return true
end

function _M.stop_server(port)
	if sockets[port] then
		sockets[port]:close()
		sockets[port] = nil
	end
end

--[[ To enable our local RPC UDP server ]]--
function _M.default_server()

	local s, err = socket.udp()
	if not s then
		_M.l_o:warn("udp():"..err)
		return nil, err
	end
	events.thread(function() sender(s) end)
	events.thread(function() receiver(s) end)
	events.periodic(_M.settings.cleaning_interval, clean_replied)
	server_run = true
end

-- return: true|false, array of responses
local function do_call(ip, port, typ, call, timeout)

	-- If no server runs, we need a default server (binded on a port choosen by
	-- the system to be able to receive replies for our rpcs)
	if not server_run then _M.default_server() end

	if _M.settings.max and not call_s then
		call_s = events.semaphore(_M.settings.max)
	end

	timeout = timeout or _M.settings.default_timeout
	
	if (timeout and _M.settings.cleaning_after and
			timeout > _M.settings.cleaning_after * 0.9) or
			(not timeout and _M.settings.cleaning_after) then
		_M.l_o:warn("do_call adjusted timeout", timeout)
		timeout = _M.settings.cleaning_after * 0.9
	end

	local datac = {key = _M.get_key()}
	if typ == "ping" then
		datac.type = "ping"
	else
		datac.type = "call"
		datac.call = call
	end

	local edatac = enc.encode(datac)
	local l = #edatac
	if l > 8192 then
		_M.l_o:warn("RPC UDP too big to be sent: "..l)
		return nil, "call length ("..l..")"
	end

	local data = {
		enc = edatac,
		key = datac.key,
		type = datac.type,
		next_try = misc.time(),
		nb_try = 0,
		ip = ip,
		port = port,
		timeout = timeout,
	}

	datac = nil

	local start_time = misc.time()

	if call_s then
		if not call_s:lock(timeout) then
			return false, "local timeout"
		end
		-- update timeout
		if timeout then
			timeout = timeout - (misc.time() - start_time)
			-- normally not possible here since lock() don't returns on timeout
			if timeout <= 0 then
				return false, "local timeout"
			end
		end
	end

	number = number + 1

	-- we store our new message in the send queue
	messages[data.key] = data

	-- wake up sender thread
	events.fire("urpc:sender")

	local ok, reply
	if timeout then
		ok, reply = events.wait("urpc:"..data.key, timeout)
	else
		ok = true
		reply = events.wait("urpc:"..data.key, timeout)
	end

	if call_s then call_s:unlock() end

	if not ok then
		return false, "timeout"
	elseif reply.error then
		return false, reply.error
	elseif reply.type == "ping" then
		return true, {true}
	else
		return true, reply.call
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
		return _M.ping(self, self.timeout)
	end

	setmetatable(p,
		{__index = function(t, func) 
			-- if __index is called, timeout == nil
			if func == "timeout" then return nil end
			return function(self, ...)
				return _M.ecall(self, {func, unpack(arg)}, self.timeout)
			end
		end})
	return p
end

return _M