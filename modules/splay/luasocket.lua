--[[
Reorganization of the LuaSocket helpers to wrap a socket but
on demand, not directly using the env.
- support for 'nodes' syntax (array with 'ip', 'port')

Modifications by Lorenzo Leonini for the Splay Project.
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

module("splay.luasocket")

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
