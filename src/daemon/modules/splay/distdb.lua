--[[
       Splay ### v1.0.1 ###
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
local math = require"math"
local string = require"string"

local assert = assert
local error = error
local ipairs = ipairs
local loadstring = loadstring
local next = next
local pairs = pairs
local pcall = pcall
local print = print
local setmetatable = setmetatable
local type = type
local tonumber = tonumber
local tostring = tostring
local unpack = unpack

module("splay.distdb")

_COPYRIGHT   = "Copyright 2011"
_DESCRIPTION = "Distributed DB functions."
_VERSION     = "0.99.0"
local db_table = {}

function put(key, value)
	if type(key) ~= "string" then
		return false, "wrong key type"
	end
	if type(value) ~= "string" and type(value) ~= "number" then
		return false, "wrong value type"
	end
	db_table[key] = value
	return true   
	--print("key: "..key..", value: "..value)
end

function get(key)
	return db_table[key]
end

