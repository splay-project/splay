--[[
       Splay ### v1.0.6 ###
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

local events = require"splay.events"
local socket = require"splay.socket"
local misc = require"splay.misc"
local net = require"splay.net"
local log = require"splay.log"
local llenc = require"splay.llenc"
local enc = require"splay.benc"

local error = error
local pairs = pairs
local pcall = pcall
local print = print
local setmetatable = setmetatable
local tostring = tostring
local tonumber = tonumber
local type = type
local unpack = unpack

module("splay.rpc")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Remote Procedure Call over TCP"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

settings = {
	max = nil, -- max outgoing RPCs
	default_timeout = 60,
	nodelay = nil -- tcp nodelay option
}

mode = "rpc"

local number = 0
local call_s = nil

function stats()
	return number
end

function infos()
	return"Number of RPCs: "..number
end

local function reply(s, data)
	local ok, err = s:send(enc.encode(data))
	if not ok then
		l_o:warn("reply send(): "..err)
	end
	return ok, err
end

local function rpc_handler(s)

	if settings.nodelay then s:setoption("tcp-nodelay", true) end
	s = llenc.wrap(s)

	local data_s, err = s:receive()
	if data_s then
		local ok, data = pcall(function() return enc.decode(data_s) end)
		if ok then
			if data.type == "call" then
				local c, err = misc.call(data.call)
				if c then
					reply(s, c)
				else
					l_o:warn("rpc_handler misc.call(): "..err)
					-- TODO good error report
					reply(s, {nil})
				end

			elseif data.type == "ping" then
				reply(s, true)
			elseif data.type == "run" then
				events.thread(function() misc.run(data.run) end)
				reply(s, true)
			end
		else
			l_o:warn("rpc_handler corrupted message:", data_s)
		end
	else
		l_o:warn("rpc_handler receive(): "..err)
	end
end

function server(port, max, backlog)
	return net.server(port, rpc_handler, max, nil, backlog)
end

function stop_server(port)
	return net.stop_server(port, true)
end

-- return: true|false, array of responses
-- timeout is the max delay for the whole RPC
local function do_call(ip, port, typ, call, timeout)

	if settings.max and not call_s then
		call_s = events.semaphore(settings.max)
	end

	timeout = timeout or settings.default_timeout
	local timeleft = timeout

	local func_name
	local data = {}
	if typ == "ping" then
		data.type = "ping"
		func_name = "*ping*"
	else
		data.type = "call"
		data.call = call
		func_name = call[1]
	end
	local err_prefix = "do_call '"..func_name.."'"

	local start_time = misc.time()

	if call_s then
		if not call_s:lock(timeleft) then
			return false, "local timeout"
		end
		if timeleft then
			-- update time left
			timeleft = timeout - (misc.time() - start_time)
			-- normally not possible here since lock() doesn't return on timeout
			if timeleft <= 0 then
				return false, "local timeout"
			end
		end
	end

	number = number + 1

	local s, err = socket.tcp()
	
	if s then
		if timeleft then s:settimeout(timeleft) end
		s = llenc.wrap(s)
		local r, err = s:connect(ip, port)
		
		if r then
			if settings.nodelay then s:setoption("tcp-nodelay", true) end

			-- update time left
			if timeleft then
				timeleft = timeout - (misc.time() - start_time)
				if timeleft <= 0 then
					s:close()
					if call_s then call_s:unlock() end
					l_o:warn(err_prefix.." before send timeout")
					return false, "timeout"
				end
				s:settimeout(timeleft)
			end

			local r, err = s:send(enc.encode(data))
			if not r then
				s:close()
				if call_s then call_s:unlock() end
				l_o:warn(err_prefix.." send(): "..err)
				return false, err
			end

			-- update time left
			if timeleft then
				timeleft = timeout - (misc.time() - start_time)
				if timeleft <= 0 then
					s:close()
					if call_s then call_s:unlock() end
					return false, "timeout"
				end
				s:settimeout(timeleft)
			end

			local r, err = s:receive()
			s:close()
			if call_s then call_s:unlock() end
	
			if r then
				if data.type == "call" then
					local ok, r = pcall(function() return enc.decode(r) end)
					if ok then
						return true, r
					else
						l_o:warn("corrupted message")
						return false, "corrupted message"
					end
				elseif data.type == "ping" then
					return true, {true}
				end
			else
				l_o:warn(err_prefix.." receive(): "..err)
				return false, err
			end
		else
			s:close()
			if call_s then call_s:unlock() end
			l_o:warn(err_prefix.." connect("..ip..":"..port.."): "..err)
			return false, err
		end
	else
		if call_s then call_s:unlock() end
		l_o:error(err_prefix.." tcp(): "..err)
		return false, err
	end
end

--------------------[[ HIGH LEVEL FUNCTIONS ]]--------------------

-- return: true|false, array of responses
function acall(ip, port, call, timeout)

	-- support for a node array with ip and port
	if type(ip) == "table" then
		if not ip.ip or not ip.port then
			l_o:warn("parameter array without ip or port")
			return false, "parameter array without ip or port"
		else
			timeout = call
			call = port
			port = ip.port
			ip = ip.ip
		end
	end
	
	if timeout ~=nil and tonumber(timeout)==nil then
		 l_o:warn("invalid timeout value: ",timeout)
		 return false, "invalid timeout value: "..timeout
	end

	if type(call) ~= "table" then
		call = {call}
	end

	return do_call(ip, port, "call", call, timeout)
end
-- DEPRECATED
function a_call(...) return acall(...) end

function ecall(ip, port, func, timeout)
	local ok, r = acall(ip, port, func, timeout)
	if ok then
		return unpack(r)
	else
		error(r)
	end
end

-- To be used when we are sure that all the rpc reply return something other
-- than nil, then nil will indicate and error. The best way to do is to use
-- acall() and then unpack the second return values or use it as an array.
function call(ip, port, func, timeout)
	local ok, r = acall(ip, port, func, timeout)
	if ok then
		return unpack(r)
	else
		return nil, r
	end
end

-- RPC ping
function ping(ip, port, timeout)
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
function proxy(ip, port)
	local p = {}
	if type(ip) == "table" then
		p.port = ip.port
		p.ip = ip.ip
	else
		p.port = port
		p.ip = ip
	end
	
	p.timeout = settings.default_timeout
	--p.timeout = 100
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
