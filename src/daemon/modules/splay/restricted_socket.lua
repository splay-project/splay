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
*** Socket restrictions ***

- Host blacklist with reverse check and wildcard (TCP + UDP)
- Maximum sockets opened (TCP + UDP)
- Listening ports range (TCP + UDP)
- Maximum sent bytes (TCP + UDP)
- Maximum received bytes (TCP + UDP)

Actually we permit max_sockets TCP sockets AND max_sockets UDP sockets.

When a socket is restricted, there is no way to get the non restricted
original socket. But you must care to don't have a non restricted version
of luasocket in the environnment.

total_received (and total_sent) will not exactly represent the network traffic
because packets headers are not accounted. But we think this is a reasonable
limitation.

Someone could abuse (one time) the max_receive limit using "*a" or "*l" pattern
with receive() that can be a lot of datas.

USAGE:

socket = require"socket.core"
rs = require"splay.restricted_socket"
rs.init(settings)
socket = rs.wrap(socket)

Full luasocket is socket.core + some shortcuts written in lua. In splay, I
restrict socket.core then I add different wrappers including the original
luasocket shortcuts.

]]

local base = _G

local socket = require"socket.core" -- needed for dns in blacklist
local string = require"string"
local math = require"math"
local log = require"splay.log"

local pairs = pairs
local print = print
local setmetatable = setmetatable
local tostring = tostring
--local setfenv = setfenv

module("splay.restricted_socket")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Restrictions for LuaSocket"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

-- vars
local total_sent = 0
local total_received = 0
local total_tcp_sockets = 0
local total_udp_sockets = 0

--[[ CONFIG ]]--

local max_send = math.huge
local max_receive = math.huge
local max_sockets = math.huge
local start_port = 1025
local end_port = 65535
local udp_options = true
local udp_drop_ratio = 0 -- [0-1000] (to use with math.random(1000))
local local_ip = nil -- if defined, authorize connections only in local port range
local blacklist = {}

local init_done = false
function init(settings)
	if not init_done then
		init_done = true
		if not settings then return false, "no settings" end

		if settings.max_send then max_send = settings.max_send end
		if settings.max_receive then max_receive = settings.max_receive end
		if settings.max_sockets then max_sockets = settings.max_sockets end
		if settings.start_port then start_port = settings.start_port end
		if settings.end_port then end_port = settings.end_port end
		if settings.blacklist then
			-- array, we need a full copy !
			for _, b in pairs(settings.blacklist) do
				blacklist[#blacklist + 1] = b
			end
		end

		if settings.local_ip then local_ip = settings.local_ip end
		if settings.udp_options then udp_options = settings.udp_options end
		if settings.udp_drop_ratio then
			udp_drop_ratio = settings.udp_drop_ratio * 1000 -- original value is [0-1]
		end

		return true
	else
		return false, "init() already called"
	end
end

-- DNS (or reverse DNS) can be long: use use_async_dns=true in luasocket.lua (default)
local function check_blacklist(target)

	if #blacklist > 0 then
		for _, v in pairs(blacklist) do
			if string.find(v, "*") then
				if string.match(target, v) then
					return false
				end
			else
				if target == v then
					l_o:notice("Blacklist refused: "..v)
					return false
				end
			end
		end

		-- REVERSE (dns to ip or ip to dns)
		local rev_target = nil
		if string.match(target, "^%d+\.%d+\.%d+\.%d+$") then -- ip
			rev_target = socket.dns.tohostname(target)
		else
			rev_target = socket.dns.toip(target)
		end

		-- (can be null if resolver fail)
		if rev_target then
			for _, v in pairs(blacklist) do
				if string.find(v, "*") then
					if string.match(rev_target, v) then
						l_o:notice("Blacklist refused: "..v)
						return false
					end
				else
					if rev_target == v then
						l_o:notice("Blacklist refused: "..v)
						return false
					end
				end
			end
		end
	end
	return true
end

--[[ MAIN ]]--

-- Create a sandbox array arround a true tcp socket. The "base" socket is only
-- an array. Only tcp(), connect(), listen() or accept() create a new socket.
local function tcp_sock_wrapper(sock)

	local new_sock = {}

	-- This socket is called with ':', so the 'self' refer to socket but, in
	-- the call, self is the wrapping table, we need to replace it by socket.
	local mt = {
		__index = function(table, key)
			return function(self, ...)
				--l_o:debug("tcp."..key.."()")
				return sock[key](sock, ...)
			end
		end,
		__tostring = function()
			return "#RS (TCP): "..tostring(sock)
		end}

	setmetatable(new_sock, mt)

	-- Restricted methods --

	if sock.receive then
		new_sock.receive = function(self, pattern, prefix)
			--l_o:debug("tcp.receive()")
			
			if total_received > max_receive then
				l_o:warn("Receive restricted (total: "..total_received..")")
				return nil, "restricted", ""
			end

			local data, msg, partial = sock:receive(pattern, prefix)
			local len = #(data or partial)
			if prefix then len = len - #prefix end
			if data and pattern == "*l" then len = len + 1 end

			total_received = total_received + len

			return data, msg, partial
		end
	end
	
	if sock.send then
		new_sock.send = function(self, data, start, stop)
			--l_o:debug("tcp.send()")

			start = start or 1
			stop = stop or #data

			if start ~= math.floor(start) or
					stop ~= math.floor(stop) or
					stop < start then
				return nil, "wrong parameters"
			end

			local len = stop - start + 1

			if total_sent + len > max_send then
				l_o:warn("Send restricted (total: "..total_sent..")")
				return nil, "restricted", 0
			end

			local n, status, last = sock:send(data, start, stop)

			local t = n or last
			if start then
				t = t - start + 1
			end

			-- There is a bug in luasocket when status = 'closed' the sent size is
			-- completly wrong (~ 150Mo...) (fixed in luasocket 2.0.2).
			if t > len then
				l_o:warn("luasocket <= 2.0.1 BUG: ", t, len)
				t = len
			end

			total_sent = total_sent + t

			return n, status, last
		end
	end

	if sock.connect then
		new_sock.connect = function(self, host, port)
			--l_o:debug("tcp.connect("..host..", "..tostring(port)..")")

			-- we only authorize our local connection on our port range
			if local_ip and host == local_ip then
				if port < start_port or port > end_port then
					l_o:warn("Local connect restricted (port: "..port..") not in job range.")
					return nil, "restricted"
				end
			else
				if not check_blacklist(host) then
					l_o:warn("Connect restricted (blacklist: "..host..")")
					return nil, "restricted"
				end
			end

			local s, m = sock:connect(host, port)

			--if s == 1 then l_o:debug("New peer: "..sock:getpeername()) end

			return s, m
		end
	end

	if sock.bind then
		new_sock.bind = function(self, address, port, backlog)
			--l_o:debug("tcp.bind("..address..", "..tostring(port)..")")

			if port < start_port or port > end_port then
				l_o:warn("Bind restricted (port: "..port..") not in job range.")
				return nil, "restricted"
			end
			if local_ip then address = local_ip end

			return sock:bind(address, port, backlog)
		end
	end

	if sock.close then
		new_sock.close = function(self)
			--l_o:debug("tcp.close()")

			if not sock:getsockname() then
				l_o:notice("Closing an already closed socket.")
			else
				total_tcp_sockets = total_tcp_sockets - 1
				--l_o:debug("Peer closed, total TCP sockets: "..total_tcp_sockets)
				sock:close()
			end
		end
	end

	-- A complete accept function that return a client wrapper
	-- recursively (not directly in tcp_sock_wrapper() because we
	-- can't call the same function internally)
	if sock.accept then
		new_sock.accept = function(self)
			--l_o:debug("tcp.accept()")
			
			-- We must accept the client first, if not, socket.select() will
			-- select it every time we don't take it, but if the number of
			-- socket is too high, we will close the socket immediately.
			local s, err = sock:accept()
			if not s then return nil, err end

			if total_tcp_sockets >= max_sockets then
				s:close()
				l_o:warn("Accept restricted, too many sockets: "..total_tcp_sockets)
				return nil, "restricted"
			end

			total_tcp_sockets = total_tcp_sockets + 1
			--l_o:debug("Peer accepted, total TCP sockets: "..total_tcp_sockets)
			--l_o:debug("New peer: "..s:getpeername())
			return tcp_sock_wrapper(s)
		end
	end
	
	return new_sock
end

-- Create a sandbox array around a true udp socket. The "base" socket is only
-- an array.
local function udp_sock_wrapper(sock)

	local new_sock = {}

	-- This socket is called with ':', so the 'self' refer to socket but, in
	-- the call, self is the wrapping table, we need to replace it by socket.
	local mt = {
		__index = function(table, key)
			return function(self, ...)
				--l_o:debug("udp."..key.."()")
				return sock[key](sock, ...)
			end
		end,
		__tostring = function()
			return "#RS (UDP): "..tostring(sock)
		end}

	setmetatable(new_sock, mt)

	-- Restricted methods --

	if sock.receive then
		new_sock.receive = function(self, ...)
			--l_o:debug("udp.receive()")
			
			if total_received > max_receive then
				l_o:warn("Receive restricted (total: "..total_received..")")
				return nil, "restricted", ""
			end

			local data, msg = sock:receive(...)
			if data then total_received = total_received + #data end

			return data, msg
		end
	end

	if sock.receivefrom then
		new_sock.receivefrom = function(self, ...)
			--l_o:debug("udp.receivefrom()")
			
			if total_received > max_receive then
				l_o:warn("Receive restricted (total: "..total_received..")")
				return nil, "restricted", ""
			end

			local data, msg, ip, port = sock:receivefrom(...)
			if data then total_received = total_received + #data end

			return data, msg, ip, port
		end
	end
	
	if sock.send then
		-- LuaSocket documentation is wrong here (say it returns 1 but
		-- it returns length)
		new_sock.send = function(self, data)
			--l_o:debug("udp.send()")

			local len = #data

			if total_sent + len > max_send then
				l_o:warn("Send restricted (total: "..total_sent..")")
				return nil, "restricted"
			end

			local n, status
			if math.random(1000) > udp_drop_ratio then
				n, status = sock:send(data)
			else
				n = len
			end

			if n then
				total_sent = total_sent + len
			end

			return n, status
		end
	end

	if sock.sendto then
		-- LuaSocket documentation is wrong here (say it returns 1 but
		-- it returns length)
		new_sock.sendto = function(self, data, ip, port)
			--l_o:debug("udp.sendto()")

			-- we only authorize our local connection on our port range
			if local_ip and ip == local_ip then
				if port < start_port or port > end_port then
					l_o:warn("Local connect restricted (port: "..port..") not in job range.")
					return nil, "restricted"
				end
			else
				if not check_blacklist(ip) then
					l_o:warn("Connect restricted (blacklist: "..ip..")")
					return nil, "restricted"
				end
			end

			local len = #data

			if total_sent + len > max_send then
				l_o:warn("Send restricted (total: "..total_sent..")")
				return nil, "restricted"
			end

			-- LuaSocket documentation is wrong here (say it returns 1 but
			-- it returns length)
			local n, status
			if math.random(1000) > udp_drop_ratio then
				n, status = sock:sendto(data, ip, port)
			else
				n = len
			end

			if n then
				total_sent = total_sent + len
			end

			return n, status
		end
	end

	if sock.setoption then
		new_sock.setoption = function(self, ...)
			--l_o:debug("udp.setoption()")

			if udp_options then
				return sock:setoption(...)
			else
				return nil, "restricted"
			end
		end
	end

	if sock.setpeername then
		new_sock.setpeername = function(self, ip, port)
			--l_o:debug("udp.setpeername()")
			
			if ip == "*" then
				return sock:setpeername("*")
			else
				-- we only authorize our local connection on our port range
				if local_ip and ip == local_ip then
					if port < start_port or port > end_port then
					l_o:warn("Local connect restricted (port: "..port..") not in job range.")
						return nil, "restricted"
					end
				else
					if not check_blacklist(ip) then
					l_o:warn("Connect restricted (blacklist: "..ip..")")
						return nil, "restricted"
					end
				end
				return sock:setpeername(ip, port)
			end

		end
	end

	if sock.setsockname then
		new_sock.setsockname = function(self, address, port)
			--l_o:debug("udp.setsockname()")
			
			if port < start_port or port > end_port then
				l_o:warn("Local connect restricted (port: "..port..") not in job range.")
				return nil, "restricted"
			end
			if local_ip then address = local_ip end

			return sock:setsockname(address, port)
		end
	end

	if sock.close then
		new_sock.close = function(self)
			--l_o:debug("udp.close()")

			if not sock:getsockname() then
				l_o:notice("Closing an already closed socket.")
			else
				total_udp_sockets = total_udp_sockets - 1
				--l_o:debug("Total UDP sockets: "..total_udp_sockets)
				sock:close()
			end
		end
	end
	
	return new_sock
end

function wrap(sock)
	if string.find(tostring(socket), "#RS") then
		l_o:warn("trying to wrap an already RS socket "..tostring(socket))
		return socket
	end

	-- The New Restricted Socket(tm)
	local new_sock = {}

	local mt = {
		-- With __index returning a function instead of a table, the inside table
		-- (sock) can't be taken from the metatable.
		--mt.__index = sock
		__index = function(table, key)
			--l_o:debug("sock."..key.."()")
			return sock[key]
		end,
		__tostring = function()
			return "#RS: "..tostring(sock) 
		end
	}

	setmetatable(new_sock, mt)

	-- Additional functions to watch limits

	new_sock.infos = function()
		local s = "Total send: "..total_sent.." (max: "..max_send..")\n"..
				"Total receive: "..total_received.." (max: "..max_receive..")\n"..
				"Total TCP sockets: "..total_tcp_sockets.." (max: "..max_sockets..")\n"..
				"Total UDP sockets: "..total_udp_sockets.." (max: "..max_sockets..")\n"..
				"Ports: "..start_port.."-"..end_port.."\n"
		if #blacklist > 0 then
			local bl_s = ""
			for _, b in pairs(blacklist) do
				bl_s = b.." "..bl_s
			end
			s = s.."Blacklist: "..bl_s.."\n"
		else
			s = s.."No blacklist\n"
		end
		if local_ip then
			s = s.."Local IP: "..local_ip
		else
			s = s.."Local IP: unknown"
		end
		return s
	end

	new_sock.limits = function()
		return max_send, max_receive, max_sockets, start_port, end_port, local_ip
	end

	new_sock.stats = function()
		return total_sent, total_received, total_tcp_sockets, total_udp_sockets
	end

	-- Create a *master* that will become a *client* or a *server* socket.
	new_sock.tcp = function()
		--l_o:debug("tcp()")

		if total_tcp_sockets >= max_sockets then
			return nil, "restricted"
		end

		local stcp, err = sock.tcp()
		if not stcp then
			return nil, err
		else
			total_tcp_sockets = total_tcp_sockets + 1
			--l_o:debug("New socket, total TCP sockets: "..total_tcp_sockets)

			return tcp_sock_wrapper(stcp)
		end
	end

	new_sock.udp = function()
		--l_o:debug("udp()")

		if total_udp_sockets >= max_sockets then
			return nil, "restricted"
		end

		local sudp, err = sock.udp()
		if not sudp then
			return nil, err
		else
			total_udp_sockets = total_udp_sockets + 1
			--l_o:debug("Total UDP sockets: "..total_udp_sockets)

			return udp_sock_wrapper(sudp)
		end
	end

	return new_sock
end
