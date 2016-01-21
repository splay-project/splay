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

local misc_core = require"splay.misc_core" -- register splay.misc
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

math.randomseed(os.time())

--module("splay.misc")
local _M= {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Some useful functions."
_M._VERSION     = 1.0

--[[ Fully duplicate an array ]]--
function _M.dup(a)
	if type(a) ~= "table" then
		return a
	else
		local out = {}
		for i, j in pairs(a) do
			out[i] = _M.dup(j)
		end
		return out
	end
end

--[[ String generation ]]--
function _M.gen_string(times, s)

	-- compatibility when 2 first parameters are swapped
	if type(times) == "string" then
		times,s=s,times
	end
	
	s = s or "a"

	if times == 0 then return "" end
	-- not needed but still faster...
	if times == 1 then return s end

	local t = math.floor(times / 2)
	if times % 2 == 0 then
		return _M.gen_string(s..s, t)
	else
		return _M.gen_string(s..s, t)..s
	end
end

function _M.split(s, sep)
       local res = {}
       sep = sep or ' '
       for v in s:gmatch('[^' .. sep .. ']+') do
               res[#res + 1] = v
       end
       return res
end


--[[ Size of a table with any kind of indexing ]]--
function _M.size(t)
	local c = 0
	for _, _ in pairs(t) do c = c + 1 end
	return c
end

--[[ Size of a numeric table, counting intermediates nil ]]--
function _M.isize(t)
	local c = 0
	for i, _ in pairs(t) do
		if type(i) == "number" then
			if i > c then c = i end
		end
	end
	return c
end

--[[ Returns the key set from a table (all keys that map to a non-nil value)]]

function _M.table_keyset(t)
	local s = {}
	for k,v in pairs(t) do
		s[#s+1] = k
	end
	return s
end

--[[ Concatenate 2 tables (duplicate elements) ]]--
-- DEPRECATED
function _M.table_concat(t1, t2)
	if not t1 and not t2 then return {} end
	if not t1 then return t2 end
	if not t2 then return t1 end
	local t = _M.dup(t1)
	for _, e in pairs(_M.dup(t2)) do t[#t + 1] = e end
	return t
end

local function _merge(t1, t2)
	if not t1 and not t2 then return nil end
	if not t1 or not next(t1) then return t2 end
	if not t2 or not next(t2) then return t1 end

	local out = {}

	if #t1 == _M.size(t1) and #t2 == _M.size(t2) then
		-- pure arrays, we consider we will concatenate things
		for _, v in ipairs(t1) do
			out[#out + 1] = v
		end
		for _, v in ipairs(t2) do
			out[#out + 1] = v
		end
	else
		-- at least one mixed array, keys from t1 have priority if there are
		-- collisions
		for k, v in pairs(t2) do
			out[k] = v
		end
		for k, v in pairs(t1) do
			out[k] = v
		end
	end

	return out
end

--[[ Try to merge x tables (2 by 2).
If they are both array, concatenate elements from the first, then from the
second. If one or more is mixed or hash, do a key based merge with priority
to the first if there are collisions.
]]
function _M.merge(...)
	local arg = {...}
	if #arg <= 2 then
		return _merge(arg[1], arg[2])
	else
		local a, b = arg[1], arg[2]
		table.remove(arg, 1)
		table.remove(arg, 1)
		return merge(_merge(a, b), unpack(arg))
	end
end

function _M.equals(e1, e2)
  if type(e1) ~= "table" then
    return e1 == e2
	elseif type(e2) == "table" then
		for k1, v1 in pairs(e1) do
			if not equal(v1, e2[k1]) then
				return false
			end
		end
		for k2, v2 in pairs(e2) do
			if not equal(v2, e1[k2]) then
				return false
			end
		end
		return true
	else
		return false
	end
end

--equal = equals -- for compatibility reasons, keep old version with typo.

function _M.empty(t)
	if next(t) then
		return false
	else
		return true
	end
end

--[[ Pick (a) random element(s) of an array (without repetitions)
If n == nil, then return one element.
If n, return an array.
]]
function _M.random_pick(a, n) -- array, number of elements to pick
	local ori_n = n
	n = n or 1

	if #a == 0 then
		if not ori_n then
			return nil
		else
			return {}
		end
	end

	if n > #a then n = #a end

	local out = {}
	local t = {}
	local r = math.random(#a)
	while #out < n do
		while t[r] do
			r = math.random(#a)
		end
		t[r] = true
		table.insert(out, a[r])
	end

	if not ori_n then
		return out[1]
	else
		return out
	end
end

-- DEPRECATED, compatibility
function _M.random_pick_one(a)
	return _M.random_pick(a)
end

function _M.shuffle(a)
	if #a == 1 then
		return a
	else
		return _M.random_pick(a, #a)
	end
end

--[[ Convert a big endian (network byte order) string into an int ]]--
function _M.to_int(s)
	local v = 0
	for i = 1, #s do
		v = v * 256 + string.byte(string.sub(s, i, i))
	end
	return v
end

--[[ Convert an integer into a string of BYTES (in network byte order) ]]--
function _M.to_string(int, size)
	if not size then size = 4 end
	local s = ""
	for i = (size - 1), 0, -1 do
		s = s..string.char(math.floor(int / (256 ^ i)))
		int = int % (256 ^ i)
	end
	return s
end

--[[ Convert and hash in hexadecimal ascii into a byte coded hash (2 * smaller) ]]--
function _M.hash_ascii_to_byte(s)
	local hash = ""
	for i = 1, #s, 2 do
		hash = hash..string.char(tonumber("0x"..string.sub(s, i, i + 1)))
	end
	return hash
end

function _M.dec_to_base(input, b)
	if input == 0 then return "0" end
	local k, out, d = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", ""
	while input > 0 do
		input, d = math.floor(input / b), math.mod(input, b) + 1
		out = string.sub(k, d, d)..out
	end
	return out
end

function _M.base_to_dec(input, b)
	if b == 10 then return input end
	input = tostring(input):upper()
	d ={[0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
		"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"}
	local r = 0
	for i = 1, #input do
		local c = string.sub(input, i, i)
		local k
		for j = 0, #d do
			if d[j] == c then
				k = j
				break
			end
		end
		r = r * b
		r = r + k
	end
	return r
end

function _M.convert_base(input, b1, b2)
	b1 = b1 or 10
	b2 = b2 or 16
	return _M.dec_to_base(_M.base_to_dec(input, b1), b2)
end

function _M.ctime()  -- time from core C lib
	return misc_core.time()
end
--[[ Unix time with precision of 1/10'000s ]]--
function _M.time()
	local s, m = misc_core.time()
	return s + m / 1000000
end

--[[ Between (circular) ]]--
-- i: index to check
-- a: start
-- b: end
function _M.between_c(i, a, b)
    if b >= a then return i > a and i < b else return i > a or i < b end
end

-- convert big or small number in scientific notation into a decimal string
function _M.to_dec_string(s)
	local s = tostring(string.format("%.0f",s))
	local start, stop = string.find(s, "e", 1, true)
	-- not scientific
	if not start then return s end

	local positif = true
	if string.sub(s, 1, 1) == "-" then
		s = tonumber(string.sub(s, 2))
		positif = false
	end

	local t = split(s, "e")
	local m, e = t[1], t[2]
	local t = split(m, ".")
	if t[2] then
		m = t[1]..t[2]
	end

	if string.sub(e, 1, 1) == "-" then
		e = tonumber(string.sub(e, 2))
		for i = 1, e - 1 do
			m = "0"..m
		end
		m = "0."..m
	else
		e = tonumber(e) - #m + 1
		for i = 1, e do
			m = m.."0"
		end
	end
	if not positif then m = "-"..m end
	return m
end

--[[ Transform an Lua object into a string. ]]--
function _M.stringify(arg)
	if type(arg) == "table" then
		local str = "{"
		for name, value in pairs(arg) do
			str = str.."[".._M.stringify(name).."] = "
			str = str.._M.stringify(value)..","
		end
		return str.."}"
	elseif type(arg) == "string" then
		r = {}
		for i = 0, 255 do
			r[string.char(i)] = "\\"..i
		end
		return "'"..string.gsub(arg, ".", r).."'"
	elseif type(arg) == "number" then
		return arg
	elseif type(arg) == "boolean" then
		if arg then return "true" else return "false" end
	elseif type(arg) == "nil" then
		return "nil"
	-- not really possible to remotly receive that...
	elseif type(arg) == "function" then
		return "'*ERR_FUNCTION*'"
	else
		return "'*ERR_UNKNOWN*'"
	end
end

function _M.assert_object(object)
	local wrapped = {}
	local mt = {
		__index = function(table, key)
			if type(object[key]) ~= "function" then
				return object[key]
			else
				return function(...)
					return assert(object[key](...))
				end
			end
		end}
	setmetatable(wrapped, mt)
	return wrapped
end

function _M.assert_function(func)
	return function(...)
		return assert(func(...))
	end
end

--[[ Call a procedure received as an indexed table.
	Table format:
	{"name_of_procedure", "arg1", "arg2", ..., "argn"}
	return and array if OK or nil, err if not OK
]]
function _M.call(procedure)
	
	local f, err = loadstring("return "..procedure[1], "call")
	if not f then
		return nil, err
	end
	f = f()

	if type(f) == "function" then
		local args = {}
		if _M.isize(procedure) > 1 then
			for i = 2, _M.isize(procedure) do
				args[i - 1] = procedure[i]
			end
		end
		return {f(unpack(args))}
	else
		if _M.isize(procedure) > 1 then
			return nil, "invalid function name: "..procedure[1]
		else
			return {f}
		end
	end
end

function _M.run(code)
	local f, err = loadstring(code, "run")
	if not f then
		return nil, err
	end
	return f()
end

function _M.throw(name, value)
	error({exception = {name, value}}, 0)
end

function _M.try(f, ecatch)
	local r = {pcall(f)}
	if not r[1] then
		if not r[2] or not r[2].exception then
			error(r[2], 0)
		end
		local found = false
		for e, f in pairs(ecatch) do
			if e == r[2].exception[1] then
				f(r[2].exception[2])
				found = true
				break
			end
		end
		if not found then
			error(r[2], 0)
		end
	end
end

-------------------------------------------------------------------------------
-- Simple set implementation based on LuaSocket's tinyirc.lua example
-- (actual code is coming from Copas)
-------------------------------------------------------------------------------
function _M.set()
	local reverse = {}
	local set = {}
	local q = {}
	setmetatable(set, { __index = {
		insert = function(set, value)
			if not reverse[value] then
				set[#set + 1] = value
				reverse[value] = #set
			end
		end,

		remove = function(set, value)
			local index = reverse[value]
			if index then
				reverse[value] = nil
				local top = set[#set]
				set[#set] = nil
				if top ~= value then
					reverse[top] = index
					set[index] = top
				end
			end
		end,

		push = function(set, key, itm)
			local qKey = q[key]
			if qKey == nil then
				q[key] = {itm}
			else
				qKey[#qKey + 1] = itm
			end
		end,

		pop = function(set, key)
			local t = q[key]
			if t ~= nil then
				local ret = table.remove(t, 1)
				if t[1] == nil then
					q[key] = nil
				end
				return ret
			end
		end
	}})
	return set
end

--Return the size of the_bytes in different units.
--It uses the 'information notation' that 1 kilobyte=1024 bytes
--See http://physics.nist.gov/cuu/Units/binary.html
function _M.bitcalc(the_bytes)
	local bits={}
	bits.bytes=the_bytes
	bits.bits=bits.bytes*8
	
	bits.kilobytes=bits.bytes/1024
	bits.kilobits=bits.bytes/128
	
	bits.megabytes=bits.kilobytes/1024
	bits.megabits= bits.kilobytes/128
	
	bits.gigabytes=bits.megabytes/1024
	bits.gigabits=bits.megabytes/128
	
	bits.terabytes=bits.gigabytes/1024
	bits.petabytes=bits.terabytes/1024
	return bits
end

return _M
