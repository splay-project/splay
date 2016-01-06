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

local json = require"cjson"
local string = require"string"

local pcall = pcall
local tostring = tostring
local type = type
local setmetatable = setmetatable

local _M = {}
_M._DESCRIPTION = "Json send and receive functions (socket wrapper) for Json4Lua"
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._VERSION     = 1.0
_M.l_o = log.new(3, "[splay.json]")

function _M.send(socket, data)
	return socket:send(json.encode(data).."\n")
end

function _M.receive(socket)
	local data, status = socket:receive("*l")
	if not data then
		return nil, status
	end
	local ok, data = pcall(function() return json.decode(data) end)
	if ok then return data else return nil, "corrupted" end
end

-- Socket wrapper
-- Use only with ':' methods or xxx.super:method() if you want to use the
-- original one.
function _M.wrap(socket, err)
	if string.find(tostring(socket), "#JSON") then
		return socket
	end

	-- error forwarding
	if not socket then return nil, err end

	local wrap_obj = {}
	wrap_obj.super = socket

	local mt = {}

	-- This socket is called with ':', so the 'self' refer to him but, in
	-- the call, self is the wrapping table, we need to replace it by the socket.
	mt.__index = function(table, key)
		if type(socket[key]) ~= "function" then
			return socket[key]
		else
			return function(self, ...)
				return socket[key](socket, ...)
			end
		end
	end
	mt.__tostring = function()
		return "#JSON: " .. tostring(socket) 
	end

	setmetatable(wrap_obj, mt)

	wrap_obj.send = function(self, data)
		return _M.send(self.super, data)
	end

	wrap_obj.receive = function(self, max_length)
		return _M.receive(self.super, max_length)
	end

	return wrap_obj
end

return _M