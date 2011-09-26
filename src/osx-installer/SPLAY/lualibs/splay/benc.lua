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
local table = require"table"
local string = require"string"

local llenc = require"splay.llenc"
local misc = require"splay.misc"

local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local type = type

module("splay.benc")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Enhanced bencoding for Lua"
_VERSION     = 1.0

local pos = 1
local data = nil

local function pop()
	local t = string.sub(data, pos, pos)
	pos = pos + 1
	return t
end

local function back()
	pos = pos - 1
end

function decode(d)

	if d then
		data = d
		pos = 1
	end

	local item = pop()

	if item == 'd' then -- dictionnary (table)
		local hash = {}
		item = pop()
		while item ~= 'e' do
			back()
			local key = decode()
			hash[key] = decode()
			item = pop()
		end
		return hash
	elseif item == 'n' then -- extension of benc
		return nil
	elseif item == 't' then -- extension of benc
		return true
	elseif item == 'f' then -- extension of benc
		return false
	elseif item == 'l' then -- list
		item = pop()
		local list = {}
		while item ~= 'e' do
			back()
			list[#list + 1] = decode()
			item = pop()
		end
		return list
	elseif item == 'i' then -- integer
		item = pop()
		local num = ''
		while item ~= 'e' do
			num = num..item
			item = pop()
		end
		return num * 1
	else -- strings (default)
		local length = 0
		while item ~= ':' do
			length = length * 10 + tonumber(item)
			item = pop()
		end
		pos = pos + length
		return string.sub(data, pos - length, pos - 1)
	end
end

--[[
Highly optimized version of encode(): avoid as much as possible
string concatanation, do it only once at the end of the table
traversal using fast table.concat.
A secondary encode_table function supports this traversal.
]]--
local function encode_table(data,out)
	local t = type(data)
	if t == 'table' then -- list(array) or hash
		local i = 1
		local list = true
		for k, v in pairs(data) do
			if k ~= i then
				list = false
				break
			end
			i = i + 1
		end
		if list then
			out[out.n] = 'l'
			out.n = out.n + 1
			for k, v in pairs(data) do
			 	encode_table(v, out)
			end
		else -- hash
			out[out.n] = 'd'
			out.n = out.n + 1
			for k, v in pairs(data) do
				encode_table(k, out)
				encode_table(v, out)
			end
		end
		out[out.n] = 'e'
	    out.n = out.n + 1
	elseif t == 'string' then
		out[out.n] = tostring(#data); 
		out.n = out.n + 1
	    out[out.n] = ":" 
		out.n = out.n + 1
		out[out.n] = data 
		out.n = out.n + 1
	elseif t == 'number' then
		-- we need to convert scientific notation to decimal
		out[out.n] = 'i' 
		out.n = out.n + 1
		out[out.n] = misc.to_dec_string(data) 
		out.n = out.n + 1
		out[out.n] = 'e' 
		out.n = out.n + 1
	elseif t == 'nil' then -- extension of benc
		out[out.n] = 'n' 
		out.n = out.n + 1
	elseif t == 'boolean' then -- extension of benc
		if data then
			out[out.n] = 't' 
			out.n = out.n + 1
		else
			out[out.n] = 'f' 
			out.n = out.n + 1
		end
	end
end
function encode(data)
	local out = { n=1 }
	encode_table(data, out)
	return table.concat(out)
end

function send(socket, data)
	return socket:send(encode(data))
end

function receive(socket)
	local data, status = socket:receive()
	if not data then
		return nil, status
	end
	local ok, data = pcall(function() return decode(data) end)
	if ok then return data else return nil, "corrupted" end
end

-- Socket wrapper
-- Use only with ':' methods or xxx.super:method() if you want to use the
-- original one.
function wrap(socket, err)
	if string.find(tostring(socket), "#BENC") then
		return socket
	end

	-- error forwarding
	if not socket then return nil, err end

	socket = llenc.wrap(socket)

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
		return "#BENC: " .. tostring(socket) 
	end

	setmetatable(wrap_obj, mt)

	wrap_obj.send = function(self, data)
		return send(self.super, data)
	end

	wrap_obj.receive = function(self, max_length)
		return receive(self.super, max_length)
	end

	return wrap_obj
end
