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

--[[
This module is an LuaSocket wrapper to use with Events thread system.

It makes socket in non-blocking mode and when data isn't there, send an events
to the Events module to wait for data.

If you set a timeout, consider that it will be the total time to complete the
full operation, for example: receive(1024 * 1024 * 1024, 10), the function will
need to receive 1Mo of data in 10 seconds or will return a timeout (even if a
part of these data is already there).

This module too extend the LuaSocket syntax to accept "node" parameter.
]]

local string = require"string"
local coroutine = require"coroutine"
local table = require"table"
local os = require"os"

local coxpcall = require"splay.coxpcall"

local misc = require"splay.misc"
local log = require"splay.log"
local socket_core = require"socket.core" -- needed for dns to ip

local assert = assert
local error = error
local pairs = pairs
local print = print
local select = select
local setmetatable = setmetatable
local tostring = tostring
local time = misc.time
local type = type
local unpack = unpack

module("splay.socket_events")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Sockets with events (to work with Events)"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

-- Try to receive and yield if needed.
--
-- If you set a timeout, the function will timeout if all the requested data are
-- not received in that time. The partial result will be returned anyway.
local function receive(socket, pattern, part, timeout)
	--l_o:debug("receive("..tostring(pattern)..")", timeout)

	local data, err, end_time
	pattern = pattern or "*l"

	if timeout then
		end_time = time() + timeout
	end

	while true do
		data, err, part = socket:receive(pattern, part)

		if data then
			return data, err, part
		else
			if err ~= "timeout" then
				-- security if user doesn't check return values, the scheduler could
				-- never be called again without this
				coroutine.yield()

				return data, err, part
			else
				if end_time then
					local ct = time()
					if end_time > ct then
						coroutine.yield("event:receive", socket, end_time - ct)
					else
						l_o:notice("receive() timeout ("..timeout..")")
						return data, err, part
					end
				else
					coroutine.yield("event:receive", socket)
				end
			end
		end
	end
end

-- Try to send data and yield if needed.
local function send(socket, data, i, j, timeout)
	--l_o:debug("send("..string.sub(data, 1, 20).."...("..string.len(data).."))", timeout)

	local n, err, sent, last, end_time
	i = i or 1
	last = i - 1

	if timeout then
		end_time = time() + timeout
	end

	while true do
		n, err, last = socket:send(data, last + 1, j)
		if n then
			return n, err, last
		else
			if err ~= "timeout" then
				-- security if user doesn't check return values, the scheduler could
				-- never be called again without this
				coroutine.yield()

				return n, err, last
			else
				if end_time then
					local ct = time()
					if end_time > ct then
						coroutine.yield("event:send", socket, end_time - ct)
					else
						l_o:notice("send() timeout ("..timeout..")")
						return n, err, last
					end
				else
					coroutine.yield("event:send", socket)
				end
			end
		end
	end
end

-- Non blocking accept()
local function accept(socket, timeout)
	--l_o:debug("accept("..tostring(timeout)..")")

	-- We need to call accept() once before giving the socket to select() if we
	-- want to be sure to non-block
	local client, err = socket:accept()
	if client then
		return wrap_tcp(client)
	end

	local end_time = nil
	if timeout then end_time = time() + timeout end

	while true do
		-- I don't know if accept() like connect() has the
		-- "Operation already in progress" error...
		if err == "timeout" or err == "timedout" or err == "Operation already in progress" then
			if end_time then
				local ct = time()
				if end_time > ct then
					coroutine.yield("event:receive", socket, end_time - ct)
				else
					l_o:notice("accept() timeout ("..timeout..")")
					return nil, "timeout"
				end
			else
				coroutine.yield("event:receive", socket)
			end
		end
		client, err = socket:accept()
		if client then
			return wrap_tcp(client)
		end
		if err ~= "timeout" and err ~= "timedout" and err ~= "Operation already in progress" then
			return nil, err
		end
	end
end

-- Non blocking connect()
local function connect(socket, ip, port, timeout)
	--l_o:debug("connect("..ip..", "..port..", "..tostring(timeout)..")")

	local _, err = nil, nil

	local end_time = nil
	if timeout then end_time = time() + timeout end

	while true do
		-- In the first loop, the socket is a tcp{master} and timeout, then it
		-- becomes a tcp{client} and "Operation already..." until it connects.
		if err == "timeout" or
				err == "timeoutd" or
				err == "Operation already in progress" then
			if end_time then
				local ct = time()
				if end_time > ct then
					coroutine.yield("event:send", socket, end_time - ct)
				else
					l_o:notice("connect() timeout ("..timeout..")")
					return nil, "timeout"
				end
			else
				coroutine.yield("event:send", socket)
			end
		end

		_, err = socket:connect(ip, port)

		if not err or err == "already connected" then
			break
		end
		if err ~= "timeout" and
				err ~= "timedout" and
				err ~= "Operation already in progress" then
			return nil, err
		end
	end
	return 1
end

local function statusHandler(status, ...)
	if status then return ... else return nil, ... end
end

local function protect(func)
	return function(...)
		return statusHandler(coxpcall.pcall(func, ...))
	end
end

local function newtry(finalizer)
	return function(...)
		local status = (...) or false
		if (status == false) then
			coxpcall.pcall(finalizer, select(2, ...))
			error((select(2, ...)), 0)
		end
		return ...
	end
end

-- Try to receive and yield if needed.
local function udp_receive(socket, from, size, timeout)
	--l_o:debug("udp_receive("..tostring(timeout)..")")

	local s = ""
	local err, port = nil, nil

	local end_time = nil
	if timeout then end_time = time() + timeout end

	while true do
		if err == "timeout" or err == "timedout" then
			if end_time then
				local ct = time()
				if end_time > ct then
					coroutine.yield("event:receive", socket, end_time - ct)
				else
					l_o:notice("receive() timeout ("..timeout..")")
					return nil, "timeout"
				end
			else
				coroutine.yield("event:receive", socket)
			end
		end

		if from then
			s, err, port = socket:receivefrom(size)
			if s then return s, err, port end -- err is IP here
		else
			s, err = socket:receive(size)
			if s then return s, err end
		end

		-- We end with all errors but timeout.
		if err ~= "timeout" and err ~= "timedout" then return nil, err end
	end
end

-- not local because accept() needs it, but should be local...
function wrap_tcp(socket)
	l_o:debug("wrap_tcp("..tostring(socket)..")")

	socket:settimeout(0)

	-- Our socket wrapper.
	local wrapped_socket = {}

	-- default timeout (nil = no timeout)
	local timeout = nil

	local mt = {
		__index = function(table, key)
			if type(socket[key]) ~= "function" then
				return socket[key]
			else
				return function(self, ...)
					if self == table then
						return socket[key](socket, ...)
					else
						return socket[key](self, ...)
					end
				end
			end
		end,
		__tostring = function()
		return "#SE (TCP): "..tostring(socket) 
	end}

	setmetatable(wrapped_socket, mt)

	if socket.send then
		wrapped_socket.send = function(self, data, i, j)
			return send(socket, data, i, j, timeout)
		end
	end

	if socket.receive then
		wrapped_socket.receive = function(self, l, prefix)
			return receive(socket, l, prefix, timeout)
		end
	end

	if socket.accept then
		wrapped_socket.accept = function(self)
			return accept(socket, timeout)
		end
	end

	if socket.connect then
		wrapped_socket.connect = function(self, ip, port)
			-- accept "node" syntax
			if type(ip) == "table" then
				port = ip.port
				ip = ip.ip
			end
			return connect(socket, ip, port, timeout)
		end
	end

	if socket.settimeout then
		wrapped_socket.settimeout = function(self, to)
			-- This is not the socket timeout, it's a high level timeout for
			-- non-blocking functions.
			--l_o:debug("settimeout("..tostring(to)..")")
			timeout = to
			-- MUST return true or something (if used in try())
			return true
		end
	end

	-- only "node" syntax
	
	if socket.bind then
		wrapped_socket.bind = function(self, ip, port)
			-- accept "node" syntax
			if type(ip) == "table" then
				port = ip.port
				ip = ip.ip
			end
			return socket:bind(ip, port)
		end
	end

	return wrapped_socket
end

local function wrap_udp(socket)
	l_o:debug("wrap_udp("..tostring(socket)..")")

	socket:settimeout(0)

	-- Our socket wrapper.
	local wrapped_socket = {}

	-- default timeout (nil = no timeout)
	local timeout = nil

	local mt = {
		__index = function(table, key)
			if type(socket[key]) ~= "function" then
				return socket[key]
			else
				return function(self, ...)
					if self == table then
						return socket[key](socket, ...)
					else
						return socket[key](self, ...)
					end
				end
			end
		end,
		__tostring = function()
		return "#SE (UDP): "..tostring(socket) 
	end}

	setmetatable(wrapped_socket, mt)

	-- NOTE send() and sendto() never block in UDP

	if socket.receive then
		wrapped_socket.receive = function(self, size)
			return udp_receive(socket, false, size, timeout)
		end
	end

	if socket.receivefrom then
		wrapped_socket.receivefrom = function(self, size)
			return udp_receive(socket, true, size, timeout)
		end
	end

	if socket.settimeout then
		wrapped_socket.settimeout = function(self, to)
			-- This is not the socket timeout, it's a high level timeout for
			-- non-blocking functions.
			--l_o:debug("settimeout("..tostring(to)..")")
			timeout = to
			-- MUST return true or something (if used in try())
			return true
		end
	end

	-- only "node" syntax
	
	if socket.sendto then
		wrapped_socket.sendto = function(self, data, ip, port)
			-- accept "node" syntax
			if type(ip) == "table" then
				port = ip.port
				ip = ip.ip
			end
			-- host resolution
			if not string.match(ip, "^%d+\.%d+\.%d+\.%d+$") then -- not ip
				ip = socket_core.dns.toip(ip)
			end
			return socket:sendto(data, ip, port)
		end
	end

	if socket.setpeername then
		wrapped_socket.setpeername = function(self, ip, port)
			-- accept "node" syntax
			if type(ip) == "table" then
				port = ip.port
				ip = ip.ip
			end
			return socket:setpeername(ip, port)
		end
	end

	if socket.setsockname then
		wrapped_socket.setsockname = function(self, ip, port)
			-- accept "node" syntax
			if type(ip) == "table" then
				port = ip.port
				ip = ip.ip
			end
			return socket:setsockname(ip, port)
		end
	end

	return wrapped_socket
end

-- wrapping of the "base" socket (still not udp or tcp)
function wrap(socket, err)
	l_o:debug("wrap("..tostring(socket)..")")
	if string.find(tostring(socket), "#SE") then
		l_o:warn("trying to wrap an already SE socket "..tostring(socket))
		return socket
	end

	if not socket.tcp then
		l_o:error("Non socket object: "..tostring(socket))
		return nil, "non_socket_object"
	end

	-- error forwarding
	if not socket then return nil, err end

	-- Our socket wrapper.
	local wrapped_socket = {}

	local mt = {
		__index = function(table, key)
			if type(socket[key]) ~= "function" then
				return socket[key]
			else
				return function(self, ...)
					if self == table then
						return socket[key](socket, ...)
					else
						return socket[key](self, ...)
					end
				end
			end
		end,
		__tostring = function()
		return "#SE: "..tostring(socket) 
	end}

	setmetatable(wrapped_socket, mt)

	wrapped_socket.protect = function(func)
		return protect(func)
	end

	wrapped_socket.newtry = function(finalizer)
		return newtry(finalizer)
	end

	wrapped_socket.tcp = function()
		local s, err = socket.tcp()
		if not s then
			return nil, err
		else
			return wrap_tcp(s)
		end
	end

	wrapped_socket.udp = function()
		local s, err = socket.udp()
		if not s then
			return nil, err
		else
			return wrap_udp(s)
		end
	end

	return wrapped_socket
end

