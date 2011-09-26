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
Socket wrapper to add llenconding capabilities (send and receive whatever
you want, including (flat) arrays). For more complexes structure
use benc or json.

You can use this module like a socket wrapper using wrap() or calling the
functions directly.

LLenc must be used with TCP (not useful with UDP, we receive whole datagrams).
]]

local string = require"string"
local math = require"math"

local tostring = tostring
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local print = print

module("splay.llenc")

_COPYRIGHT = "Copyright 2006 - 2011"
_DESCRIPTION = "LLenc send and receive functions (socket wrapper or standalone)"
_VERSION     = 1.3

function encode(data)
	if type(data) ~= "string" then
		data = tostring(data)
	end
	return #data.."\n"..data
end

local function send_one(s, data)
	if type(data) ~= "string" then
		data = tostring(data)
	end
	-- depending of the length, lua concatenation can takes more time
	local length = #data
	if length < 8192 then
		return s:send(length.."\n"..data)
	else
		local ok, status = s:send(length.."\n")
		if ok then
			return s:send(data)
		else
			return nil, status
		end
	end
end

local function send_array(s, t)
	local data = ""
	for _, e in ipairs(t) do
		data = data..encode(e)
	end
	return s:send(data)
end

function send(s, data)
	if not data then return nil, "no data" end
	if type(data) == "table" then
		return send_array(s, data)
	else
		return send_one(s, data)
	end
	return nil, "not sendable type"
end

function receive(s, max_length)
	local max_length = max_length or math.huge
	
	local length, status = s:receive("*l")
	if not length then
		return nil, status
	end
	length = tonumber(length)

	if length > max_length then
		return nil, "Too much data (max: "..max_length..")"
	end

	return s:receive(length)
end

-- return array of results or nil, error, already_received_results
function receive_array(s, number, max_length)
	number = number or 1
	local r = {}
	local c = 0
	while c < number do
		c = c + 1
		local d, err = receive(s, max_length)
		-- even 1 error, we return only the error and not an array
		if not d then return nil, err, r end
		r[#r + 1] = d
	end
	return r
end

-- Socket wrapper
-- Use only with ':' methods or xxx.super:method() if you want to use the
-- original one.
function wrap(socket, err)
	if string.find(tostring(socket), "#LLENC") then
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
		return "#LLENC: " .. tostring(socket) 
	end

	setmetatable(wrap_obj, mt)

	wrap_obj.send = function(self, data)
		return send(self.super, data)
	end

	wrap_obj.receive_array = function(self, number, max_length)
		return receive_array(self.super, number, max_length)
	end

	wrap_obj.receive = function(self, max_length)
		return receive(self.super, max_length)
	end

	return wrap_obj
end
