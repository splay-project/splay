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

require"splay_core" -- => register "splay"

local io = require"io"
local math = require"math"
local socket = require"socket.core" -- LuaSocket

local tostring = tostring
local print = print
local flush = io.flush
local os = os

module("splay")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Splay functions."
_VERSION     = 1.0

--[[
Check a port range, do a list with all ports already bound.
--]]
function check_ports(port_min, port_max)

	local refused_ports = {}

	for port = port_min, port_max do
		local s = socket.tcp()
		local status, err = s:bind('*', port)
		if status == nil then
			refused_ports[#refused_ports + 1] = port
		end
		s:close()
	end

	if #refused_ports == 0 then
		return true
	else
		return false, refused_ports
	end
end

local tcp_binded_ports = {}
local udp_binded_ports = {}

function release_ports(min, max)
	if max < min then return end
	for port = min, max do
		if tcp_binded_ports[port] then
			tcp_binded_ports[port]:close()
			tcp_binded_ports[port] = nil
		end
		if udp_binded_ports[port] then
			udp_binded_ports[port]:close()
			udp_binded_ports[port] = nil
		end
	end
end

--[[
Try to reserve (bind) a range of TCP and UDP ports.
--]]
function reserve_ports(min, max)
	if max < min then return false, "no valid range" end
	local stop, s, ok, err, last_port = false, nil, nil, nil, min

	for port = min, max do
		s, err = socket.tcp()
		if s then
			ok, err = s:bind('*', port)
			if ok then
				tcp_binded_ports[port] = s
			else
				s:close()
				stop = true
				last_port = port
				break
			end
		else
			stop = true
			last_port = port
			break
		end
	end

	if not stop then
		for port = min, max do
			local s, err = socket.udp()
			if s then
				local ok, err = s:setsockname('*', port)
				if ok then
					udp_binded_ports[port] = s
				else
					s:close()
					last_port = port
					stop = true
					break
				end
			else
				stop = true
				last_port = port
				break
			end
		end
	end

	if stop then
		release_ports(min, last_port - 1)
		return false, err, last_port
	else
		return true
	end
end

function dir_exists(dir)
	local f, err = io.open(dir)
	if not f then return false, err end
	-- We need to checkif it's a directory trying to read it like a file...
	local ok, err, code = f:read("*a")
	f:close()
	-- TODO very probably not portable...
	if code == 21 then
		return true
	else
		return false, err
	end
end

function dir_writable(dir)
	local name = dir.."/write_test_"..tostring(math.random(1000000, 1000000000))
	local f, err = io.open(name, "w")
	if f then
		local w, err = f:write("a")
		f:close()
		-- TODO not portable
		os.execute("rm -fr "..name.." > /dev/null 2>&1")
		if w then
			return true
		else
			return false, err
		end
	else
		return false, err
	end
end
