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

local string = require"string"
local pairs = pairs
local type = type

module("splay.bits")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Bits manipulation"
_VERSION     = 1.0

function init(bits, size)
	for i = 1, size do
		bits[i] = false
	end
end

--[[ Transform an ASCII string into a bits table ]]--
function ascii_to_bits(s, max_length)

	if not s then return nil end
	if not max_length then max_length = string.len(s) * 8 end
	local bits = {}
	local b_i = 1 -- bits index

	for i = 1, string.len(s) do
		local int = string.byte(string.sub(s, i, i))

		j = 256
		while j > 1 and b_i <= max_length do
			if int >= j / 2 then
				bits[b_i] = true
				int = int - j / 2
			else
				bits[b_i] = false
			end
			b_i = b_i + 1
			j = j / 2
		end
	end

	return bits
end

--[[ Transform a bit table into an ASCII string ]]--
function bits_to_ascii(bits)
	if not bits then return nil end
	local s = ""
	for i = 1, #bits, 8 do
		local int = 0
		for j = 0, 7 do
			int = int * 2
			if bits[i + j] then
				int = int + 1
			end
		end
		s = s..string.char(int)
	end
	return s
end

--[[ Pretty print bits table ]]--
function show_bits(bits)
	if type(bits) == "string" then
		bits = ascii_to_bits(bits)
	end
	local out = ""
	for i = 1, #bits do
		if bits[i] == true then
			out = out.."1"
		else
			out = out.."0"
		end
		if i % 8 == 0 then
			out = out.." "
		end
	end
	return out
end

function is_set(bits, bit)
	if type(bits) == "string" then
		bits = ascii_to_bits(bits)
	end
	return bits[bit]
end

-- Number of '1' in the bitmask
function count(bits)
	if type(bits) == "string" then
		bits = ascii_to_bits(bits)
	end
  local c = 0
  for _, j in pairs(bits) do
    if j == true then c = c + 1 end
  end
  return c
end

-- Size of the bit mask
function size(bits)
	if type(bits) == "string" then
		bits = ascii_to_bits(bits)
	end
	local c = 0
	for _, _ in pairs(bits) do c = c + 1 end
	return c
end

-- deprecated
function set(d, bit)
	d[bit] = true
end

