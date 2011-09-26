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
local log = require"splay.log"

local pcall = pcall
local print = print
local tostring = tostring
local type = type
local pairs = pairs

module("splay.net")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Network related functions, objects, .."
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

settings = {
	timeout = 600,
	connect_timeout = 60
}

local _s_s = {}

--[[ Runs multiple callbacks for a socket:
handler[1] => receive(socket [, connect])
handler[2] => send(socket [, connect])
handler[3] => initialize(socket [, connect])
handler[4] => finalize(socket [, connect])

If initialize return false, other handlers will not be executed.
--]]

local function async(sc, handler, s_s, connect)
	events.thread(function()
		local sc_string = tostring(sc)

		if handler[1] then handler.receive = handler[1] end
		if handler[2] then handler.send = handler[2] end
		if handler[3] then handler.initialize = handler[3] end
		if handler[4] then handler.finalize = handler[4] end

		local init = true
		if handler.initialize then
			local ok, msg = pcall(function() handler.initialize(sc, connect) end)
			if not ok or msg == false then init = false end
			if not ok then l_o:warning("async initialize: "..msg) end
		end

		if init then
			local t_r, t_s
			if handler.receive then
				t_r = events.thread(function()
					local ok, msg = pcall(function() handler.receive(sc, connect) end)
					if not ok then l_o:warning("async receive: "..msg) end
					events.fire("net:wait_"..sc_string)
				end)
			end

			if handler.send then
				t_s = events.thread(function()
					local ok, msg = pcall(function() handler.send(sc, connect) end)
					if not ok then l_o:warning("async send: "..msg) end
					events.fire("net:wait_"..sc_string)
				end)
			end

			if handler.receive or handler.send then
				events.wait("net:wait_"..sc_string)
				events.kill({t_r, t_s})
			end
			
			l_o:notice("async end: "..sc_string)

			if handler.finalize then
				local ok, msg = pcall(function() handler.finalize(sc, connect) end)
				if not ok then l_o:warning("async finalize: "..msg) end
			end
		end

		sc:close()
		if s_s then s_s:unlock() end
	end)
end

function client(ip, port, handler, timeout)
	if type(ip) == "table" then
		timeout = handler
		handler = port
		port = ip.port
		ip = ip.ip
	end
	timeout = timeout or settings.connect_timeout

	local s, msg = socket.tcp()
	if s then
		s:settimeout(timeout)
		local ok, msg = s:connect(ip, port)
		if ok then
			s:settimeout(settings.timeout)
			async(s, handler, nil, true)
		else
			l_o:warning("Cannot connect peer "..ip..":"..port..": "..msg)
			s:close()
		end
	else
		l_o:warning("Cannot create a new socket: "..msg)
	end
end

-- Additionnal socket functions
function server(port, handler, max, filter, backlog)

	-- compatibility when 2 first parameters where swapped
	if type(port) == "function" then
		local tmp = port
		port = handler
		handler = tmp
	end

	-- compatibility when filter was no_close
	local no_close = false
	if filter and type(filter) ~= "function" then
		no_close = filter
		filter = nil
		l_o:warn("net.server() option 'no_close' is no more supported, check doc")
	end
	local ip="*"
	if type(port) == "table" then
		if port.ip then ip=port.ip end
		port = port.port
	end
	local s, err = socket.bind(ip, port, backlog)
	if not s then
		l_o:warn("server bind("..port.."): "..err)
		return nil, err
	end
	if _s_s[port] then
		return nil, "server still not stopped"
	end
	_s_s[port] = {s = s, clients = {}}
	return events.thread(function()
		local s_s
		if max then s_s = events.semaphore(max) end
		while true do
			if s_s then s_s:lock() end
			local sc, err = s:accept()
			if sc then
				local ok = true

				if filter then
					local ip, port = sc:getpeername()
					ok = filter(ip, port)
					if not ok then
						l_o:notice("Refused by filter", ip, port)
					end
				end

				if ok then
					_s_s[port].clients[sc] = true
					if type(handler) == "function" then
						events.thread(function()
							local ok, msg = pcall(function() handler(sc) end)
							if not ok then l_o:warning("handler: "..msg) end
							if _s_s[port] then
								_s_s[port].clients[sc] = nil
							end
							if not no_close then
								sc:close()
							end
							if s_s then s_s:unlock() end
						end)
					elseif type(handler) == "table" then
						async(sc, handler, s_s)
					else
						return nil, "invalid handler"
					end
				else
					sc:close()
					if s_s then s_s:unlock() end
				end
			else
				if s_s then s_s:unlock() end
				if _s_s[port].stop then
					l_o:warn("server on port "..port.." stopped")
					_s_s[port] = nil
					break
				else
					l_o:warn("server accept(): "..err)
				end
				events.yield()
			end
		end
	end)
end

function stop_server(port, kill_clients)
	if type(port) == "table" then
		port = port.port
	end
	if _s_s[port] then
		_s_s[port].s:close()
		if kill_clients then
			for s, _ in pairs(_s_s[port].clients) do
				s:close()
			end
		end
		_s_s[port].stop = true
		-- Avoid a server() just after stop_server()
		-- (let accept() the time to "crash" and to close/clean the port)
		events.sleep(0.1)
	end
end

--[[ Generate a new UDP object:
-- - A server with an handler or generating events
-- - A socket to send datagrams
-- Only use one socket.
--]]
function udp_helper(port, handler)
	if type(port) == "function" then
		local tmp = port
		port = handler
		handler = tmp
	end
	if type(port) == "table" then
		port = port.port
	end
	local u, err, r = {}
	u.s, err = socket.udp()
	if not u.s then return nil, err end
	r, err = u.s:setsockname("*", port)
	if not r then return nil, err end

	u.server = events.thread(function()
		while true do
			local data, ip, port = u.s:receivefrom()
			if data then
				if handler then
					events.thread(function() handler(data, ip, port) end)
				else
					events.fire("udp:"..port, {data, ip, port})
				end
			else
				-- impossible without timeout...
			end
		end
	end)
	
	return u
end


