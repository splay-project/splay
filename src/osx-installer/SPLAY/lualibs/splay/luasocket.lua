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
Reorganization of the LuaSocket helpers to wrap a socket but
on demand, not directly using the env.
- support for 'nodes' syntax (array with 'ip', 'port')

Modifications by Lorenzo Leonini for the Splay Project.

Extended by Valerio Schiavoni to support Async-DNS via external async-dns module.
--]]

-----------------------------------------------------------------------------
-- LuaSocket helper module
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-----------------------------------------------------------------------------
local base = _G
local string = require("string")
local math = require("math")
local async_dns=require("splay.async_dns")

local misc=require"splay.misc"
local log = require"splay.log"

local error = error
local pairs = pairs
local print = print
local assert= assert
module("splay.luasocket")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "LuaSocket helper module"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

--[[
Set use_async_dns=false to use the default LuaSocket's blocking DNS resolution.
This is discouraged, as it introduces the single element in the Splay Runtime
that rely on blocking sockets. This option is offered as emergency solution
in case of errors.
--]]
local use_async_dns=true

function wrap(socket, err)

	if socket.connect then
		-- Already luasocket additionnal function...
		return socket
	end

	-- error forwarding
	if not socket then return nil, err end

	-----------------------------------------------------------------------------
	-- Exported auxiliar functions
	-----------------------------------------------------------------------------

	socket.connect = function(ip, port, lip, lport)
		-- accept "node" syntax
		if base.type(ip) == "table" then
			lport = lip
			lip = port
			port = ip.port
			ip = ip.ip
		end
		if base.type(lip) == "table" then
			lport = lip.port
			lip = lip.ip
		end

		local sock, err = socket.tcp()
		if not sock then return nil, err end
		if lip then
			local res, err = sock:bind(lip, lport, -1)
			if not res then
				-- LEO add
				sock:close()
				return nil, err
			end
		end
		local res, err = sock:connect(ip, port)
		if not res then
			-- LEO add
			sock:close()
			return nil, err
		end
		return sock
	end

	socket.bind = function(ip, port, backlog)
		if base.type(ip) == "table" then
			backlog = port
			port = ip.port
			ip = ip.ip
		end

		local sock, err = socket.tcp()
		if not sock then return nil, err end
		sock:setoption("reuseaddr", true)
		local res, err = sock:bind(ip, port)
		if not res then return nil, err end
		res, err = sock:listen(backlog)
		if not res then return nil, err end
		return sock
	end

	socket.choose = function(table)
		return function(name, opt1, opt2)
			if base.type(name) ~= "string" then
				name, opt1, opt2 = "default", name, opt1
			end
			local f = table[name or "nil"]
			if not f then base.error("unknown key (".. base.tostring(name) ..")", 3)
			else return f(opt1, opt2) end
		end
	end

	socket.try = socket.newtry()
	-- async-dns
	if use_async_dns then
		local dns=async_dns.resolver()		
		local function send_receive(o,field)
			local q,in_cache=dns:encode_q(o, field:gsub("[^%s]+", string.upper))	 
			if in_cache then
				return q[1][field],q
			else
				local sock,err = socket.udp()
				if not sock then return nil, err end
				--assert(sock:setsockname('*', 0)==1) --0 has problem under sandbox restrictions..
				sock:settimeout(15)
				local m=nil
				for i=1,misc.size(async_dns.dns_servers) do
					 sock:setpeername(async_dns.dns_servers[i],53)
					 sock:send(q)
					 m = sock:receive()
					 if m then break end
				end	
				sock:close()		
				if not m then l_o:error("All DNS servers failed"); return end
		    	local r=dns:decode_and_cache(m)			
				local first,full= dns:read_response(r,field)
				if first then
					--add some fields to be LuaSocket-compatible
					if field=='a' then full.name=o
					elseif field=='ptr' then full.name=first end
					full.alias={} --TODO
					full.ip={}
					--l_o:debug("Content of full.answer, to be filled in full.ip:")
					for k,v in pairs(full.answer) do
						full.ip[k]= v[field]
					end
				else
					full="host not found"
				end
				return first, full
			end
		end	
		socket.dns.toip = function(address)
			return send_receive(address, "a")
		end
		socket.dns.tohostname = function(ip)
			if ip=="127.0.0.1" then
				local l={}
				l.name="localhost"
				l.ip={"127.0.0.1"}
				l.alias={}
				return l.name, l
			end
		
			local address=ip:gsub("(%d+)%.(%d+)%.(%d+)%.(%d+)", "%4.%3.%2.%1.in-addr.arpa.")	
			return send_receive(address, "ptr")
		end
	end
	-----------------------------------------------------------------------------
	-- Socket sources and sinks, conforming to LTN12
	-----------------------------------------------------------------------------
	-- create namespaces inside LuaSocket namespace
	socket.sourcet = {}
	socket.sinkt = {}

	socket.BLOCKSIZE = 2048

	socket.sinkt["close-when-done"] = function(sock)
		return base.setmetatable({
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, {
			__call = function(self, chunk, err)
				if not chunk then
					sock:close()
					return 1
				else return sock:send(chunk) end
			end
		})
	end

	socket.sinkt["keep-open"] = function(sock)
		return base.setmetatable({
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, {
			__call = function(self, chunk, err)
				if chunk then return sock:send(chunk)
				else return 1 end
			end
		})
	end

	socket.sinkt["default"] = socket.sinkt["keep-open"]

	socket.sink = socket.choose(socket.sinkt)

	socket.sourcet["by-length"] = function(sock, length)
		return base.setmetatable({
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, {
			__call = function()
				if length <= 0 then return nil end
				local size = math.min(socket.BLOCKSIZE, length)
				local chunk, err = sock:receive(size)
				if err then return nil, err end
				length = length - string.len(chunk)
				return chunk
			end
		})
	end

	socket.sourcet["until-closed"] = function(sock)
		local done
		return base.setmetatable({
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, {
			__call = function()
				if done then return nil end
				local chunk, err, partial = sock:receive(socket.BLOCKSIZE)
				if not err then return chunk
				elseif err == "closed" then
					sock:close()
					done = 1
					return partial
				else return nil, err end
			end
		})
	end

	socket.sourcet["default"] = socket.sourcet["until-closed"]

	socket.source = socket.choose(socket.sourcet)

	return socket
end
