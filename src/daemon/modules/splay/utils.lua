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

local table = require"table"
local string = require"string"
local io = require"io"

local misc = require"splay.misc"
local base = _G
local log = require"splay.log"
local pairs = pairs
local print = print
local type = type
local tostring = tostring
local tonumber = tonumber
local collectgarbage = collectgarbage
local gcinfo = gcinfo

local arg = arg

--module("splay.utils")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Some useful functions (only for local dev)"
_M._VERSION     = 1.0
_M.l_o = log.new(3, "[splay.utils]")


-- shortcuts
function _M.pk(...) return _M.package(...) end
function _M.pr(...) return _M.print_r(...) end

--[[
Insert command line arguments in the form 'a=b' into the arg table, but
using 'a' as the index for value 'b'.
]]
function _M.args()
	if arg then
		for i = 1, #arg do
			local s = misc.split(arg[i], "=")
			if #s > 1 then
				arg[s[1]] = s[2]
			end
		end
	end
end

function _M.size(a)
	local c = 1
	for _, _ in pairs(a) do
		c = c + 1
	end
	return c
end

function _M.package()
	for i, j in pairs(base.package.loaded) do
		print(i, j)
	end
end

function _M.print_r(a, l, p)
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
	
function _M.mem(ret)
	collectgarbage()
	collectgarbage()
	local s = gcinfo() .. " ko"
	if not ret then
		print("Memory: " .. s)
	else
		return s
	end
end

function _M.generate_job(position, number, first_port, list_size, random)
	position = tonumber(position)
	number = tonumber(number or 50)
	first_port = tonumber(first_port or 20000)
	list_size = tonumber(list_size or number)
	local job = {}
	job.me = {ip = "127.0.0.1", port = first_port + position - 1}
	job.position = position
	local nodes = {}
	local jobnodes_array = nil
	for i = 1, number do
		table.insert(nodes, {ip = "127.0.0.1",  port = first_port + i - 1})
	end
	if random then
		job.list_type = "random"
		table.remove(nodes, position)
		jobnodes_array = misc.random_pick(nodes, list_size)
	else
		job.list_type = "head"
		if list_size < #nodes then
			jobnodes_array = {}
			for i = 1, list_size do
				table.insert(jobnodes_array, nodes[i])
			end
		else
			jobnodes_array = nodes
		end
	end
	job.nodes = jobnodes_array --in local mode, no churn allowed
	job.get_live_nodes = function() return jobnodes_array end -- same function as in recent splay versions
	return job
end

return _M
