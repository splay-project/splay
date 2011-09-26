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
local io = require"io"

local misc = require"splay.misc"
local base = _G
local pairs = pairs
local print = print
local type = type
local tostring = tostring
local tonumber = tonumber
local collectgarbage = collectgarbage
local gcinfo = gcinfo

local arg = arg

module("splay.utils")

_COPYRIGHT   = "Copyright 2006 - 2011"
_DESCRIPTION = "Some useful functions (only for local dev)"
_VERSION     = 1.0

-- shortcuts
function pk(...) return package(...) end
function pr(...) return print_r(...) end

--[[
Insert command line arguments in the form 'a=b' into the arg table, but
using 'a' as the index for value 'b'.
]]
function args()
	if arg then
		for i = 1, #arg do
			local s = misc.split(arg[i], "=")
			if #s > 1 then
				arg[s[1]] = s[2]
			end
		end
	end
end

function size(a)
	local c = 1
	for _, _ in pairs(a) do
		c = c + 1
	end
	return c
end

function package()
	for i, j in pairs(base.package.loaded) do
		print(i, j)
	end
end

function print_r(a, l, p)
	local l = l or 2 -- level
	local p = p or "" -- indentation (used recursivly)
	if type(a) == "table" then
		if l > 0 then
			for k, v in pairs(a) do
				io.write(p .. "[" .. tostring(k) .. "]\n")
				print_r(v, l -1, p .. "    ")
			end
		else
			print(p .. "*table skipped*")
		end
	else
		io.write(p .. tostring(a) .. "\n")
	end
end
	
function mem(ret)
	collectgarbage()
	collectgarbage()
	local s = gcinfo() .. " ko"
	if not ret then
		print("Memory: " .. s)
	else
		return s
	end
end

function generate_job(position, number, first_port, list_size, random)
	position = tonumber(position)
	number = tonumber(number or 50)
	first_port = tonumber(first_port or 20000)
	list_size = tonumber(list_size or number)
	local job = {}
	job.me = {ip = "127.0.0.1", port = first_port + position - 1}
	job.position = position
	local nodes = {}
	for i = 1, number do
		table.insert(nodes, {ip = "127.0.0.1",  port = first_port + i - 1})
	end
	if random then
		job.list_type = "random"
		table.remove(nodes, position)
		job.nodes = misc.random_pick(nodes, list_size)
	else
		job.list_type = "head"
		if list_size < #nodes then
			job.nodes = {}
			for i = 1, list_size do
				table.insert(job.nodes, nodes[i])
			end
		else
			job.nodes = nodes
		end
	end
	return job
end
