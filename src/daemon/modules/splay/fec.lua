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

--REQUIRED LIBRARIES

local table = require"table"
local math = require"math"
local string = require"string"
--for logging
local log = require"splay.log"
--for Reed-Solomon coding
local fec = require"luazfec"

--REQUIRED FUNCTIONS AND OBJECTS

local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber

--naming the module
module("splay.fec")

--authoring info
_COPYRIGHT   = "Copyright 2012 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Reed-Solomon codec."
_VERSION     = "1.0"

l_o = log.new(3, "[".._NAME.."]")

--printable_src: true if the plaintext is printable. if false, the chain of bytes is printed in decimal form
printable_src = true
--short_byte_print: used when printing non-printable strings; when true, only the first and last 3 bytes are printed
short_byte_print = true

--block2str: used to convert a string with non-printable characters into a chain of bytes in decimal format
function block2str(block)
	--initializes block_str as an empty string
	local block_str = ""
	--block_sz is the length of the string
	local block_sz = block:len()
	--if printing the short version
	if short_byte_print then
		--appends the first 3 bytes and "..."
		block_str = block_str..block:byte(1).." "..block:byte(2).." "..block:byte(3).." ... "
		--appends the last 3 bytes
		block_str = block_str..block:byte(block_sz-2).." "..block:byte(block_sz-1).." "..block:byte(block_sz)
	--if not, prints all bytes
	else
		--appends all but the last byte and a trailing space that separates them
		for i=1,block_sz-1 do
			block_str = block_str..block:byte(i).." "
		end
		--the last byte does not have a trailing space
		block_str = block_str..block:byte(block_sz)
	end
	return block_str
end



--function encode: takes the single string plaintext, splits it in k pieces, and performs fec.encode with k and m=k+n over it. It returns an array of n strings (coded blocks)
function encode(plaintext, k, n)

	--checks how much it has to pad at the end
	local need_for_padding = ((#plaintext-1) % k)+1
	--adds padding full of 0s
	local str_padding = string.rep("0", k-need_for_padding)
	--appends str_padding to the file content
	plaintext = plaintext..str_padding
	
	--initializes src as an empty table
	local src = {}
	--sz is the size of an entry of src; equal to the size of the file content (after padding) divided by k
	local sz = #plaintext/k
	--m is k+n (total number of blocks)
	local m = k+n

	--for 1 to k
	for i=1,k do
		--fills up the src table with pieces of the file content
		src[i] = plaintext:sub(1+((i-1)*sz), i*sz)
	end

	--initializes block_nums as an empty table
	local block_nums = {}

	--table has contiguous numbers starting from k up to m-1
	for i=k,(m-1) do
		table.insert(block_nums, i)
	end

	--increments sz by 1 to consider the \0 at the end of a C string
	sz = sz+1

	--debug printing: prints all processed input data
	l_o:debug("encode: need_for_padding= "..(need_for_padding%3))
	l_o:debug("encode: str_padding= \""..str_padding.."\"")
	l_o:debug("encode: k= "..k..", m= "..m)
	for i,v in ipairs(src) do
		if printable_src then
			l_o:debug("encode: src["..i.."]= \""..v.."\"")
		else
			l_o:debug("encode: src["..i.."]= \""..block2str(v).."\"")
		end
	end
	for i,v in ipairs(block_nums) do
		l_o:debug("encode: block_nums["..i.."]= "..v)
	end
	l_o:debug("encode: sz= "..sz)
	
	l_o:debug("encode: START OF C CODE")
	
	--calls encode from luazfec
	local fecs = fec.encode(k, m, src, block_nums, #block_nums, sz)

	l_o:debug("encode: END OF C CODE\n")
	
	--calculates the max number of digits in block_nums
	local block_max_digits = math.floor(math.log10(k+m))+1
	--creates a format to have a standard block size
	local block_num_format = "%0"..block_max_digits.."d"
	--adds the tag "block_num:" to the beginning of the blocks, to identify them
	
	--for all output blocks
	for i=1,#fecs do
		--generates a string with fixed size (max number of digits) containing the block number
		local padded_block_num = string.format(block_num_format, block_nums[i])
		--debug printing: prints output blocks with their respective tags
		l_o:debug("encode: fecs["..i.."]= tag:\""..padded_block_num.."\", \""..block2str(fecs[i]).."\"")
		--embeds the tag at the beginning of the block
		fecs[i] = padded_block_num..":"..fecs[i]
	end
	
	return fecs
end

--function decode: takes an array of k blocks, extracts the block_nums and performs fec.decode with k and m=k+n over it. It returns the concatenation of the output blocks
function decode(encoded, k, n)
	--TODO revisar si es posible leer el size de una tabla en el binding de C
	--TODO: bind fec_t struct to Lua. For the moment, this will be done inside encode

	--initializes inpkts and index as empty tables
	local inpkts = {}
	local index = {}
	--separator is the position where Lua first finds the character ":"
	local separator = encoded[1]:find(":")
	--for all ipairs of encoded
	for i,v in ipairs(encoded) do
		--from the format index:inpkt, it takes the substring after the separator ":" as inpkts
		inpkts[i] = v:sub(separator+1)
		--and the number before the separator as index
		index[i] = tonumber(v:sub(1, separator-1))
	end

	--num_index is the size of index
	local num_index = #index
	--sz is the size of the strings in the array inpkts + 1 (counting the \0 at the end of a C string)
	local sz = #(inpkts[1])+1
	--m is k+n (number of secondary blocks)
	local m = k+n


	--debug printing: prints all processed input data
	l_o:debug("decode: k= "..k)
	l_o:debug("decode: m= "..m)
	for i,v in ipairs(inpkts) do
		l_o:debug("encode: inpkts["..i.."]= \""..v.."\"")
	end
	for i,v in ipairs(index) do
		l_o:debug("decode: index["..i.."]= "..v)
	end
	l_o:debug("decode: num_index="..num_index)
	l_o:debug("decode: sz="..sz)

	l_o:debug("decode: START OF C CODE")

	--calls decode from luazfec
	local outpkts = fec.decode(k, m, inpkts, index, num_index, sz)

	l_o:debug("decode: END OF C CODE")
	
	--debug printing: prints output blocks
	for i,v in ipairs(outpkts) do
		if printable_src then
			l_o:debug("decode: outpkts["..i.."]= \""..v.."\"")
		else
			l_o:debug("decode: outpkts["..i.."]= \""..block2str(v).."\"")
		end
	end

	--initializes decoded as an empty string
	local decoded = ""
	--for 1 to k
	for i=1,k do
		--appends each of the blocks to construct the original string
		decoded = decoded..outpkts[i]
	end

	--debug printing: prints decoded string
	if printable_src then
		l_o:debug("decode: decoded= \""..decoded.."\"")
	else
		l_o:debug("decode: decoded= \""..block2str(decoded).."\"")
	end

	return decoded
end