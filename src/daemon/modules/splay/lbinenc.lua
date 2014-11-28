local string = require"string"

local lbinenc=require"luabins"
local misc = require"splay.misc"
local table = table
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local type = type

--module("splay.lbinenc")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Binary encoding for Splay with https://github.com/agladysh/luabins"
_M._VERSION     = 1.0

function _M.decode(d)
	local res, data = lbinenc.load(d)
	return data
end

function _M.encode(data)
	return lbinenc.save(data)
end

function _M.send(socket, data)
	return socket:send(encode(data))
end

function _M.receive(socket)
	local data, status = socket:receive()
	if not data then
		return nil, status
	end
	local ok, data = pcall(function() return _M.decode(data) end)
	if ok then return data else return nil, "corrupted" end
end

-- Socket wrapper
-- Use only with ':' methods or xxx.super:method() if you want to use the
-- original one.
function wrap(socket, err)
	if string.find(tostring(socket), "#LBINENC") then
		return socket
	end

	-- error forwarding
	if not socket then return nil, err end

	--socket = llenc.wrap(socket)

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
		return "#LBINENC: " .. tostring(socket) 
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