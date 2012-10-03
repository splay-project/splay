--[[
	Splayd
	Copyright 2010 Jose Valerio (University of Neuchâtel)
	http://www.splay-project.org
]]

--[[
This file is part of Splayd.

Splayd is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

Splayd is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
Splayd.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[

Restricted DataBase
-------------

Provides a sandboxed version of the Kyoto Cabinet DB v2.24

permitted APIs:

db.open(table_name, mode) --mode: hash, tree
db.exists(table_name)
db.check(table_name, key)
db.size(table_name)
db.remove(table_name)
db.get(table_name, key)
db.set(table_name, key, value)
db.close(table_name)
db.count(table_name)
db.clear(table_name)
replace(table_name, key, value)
pairs(table_name)
remove(table_name, key)
synchronize(table_name)
get(table_name, key)
set(table_name, key, value)
close(table_name)

]]

local string = require"string"
local print = print
local type = type
local orig_pairs = pairs
local kc = require"kyotocabinet"
local io = require"io"
local crypto = require"crypto"
local evp = crypto.evp
local log = require"splay.log"
--local rio = require"splay.restricted_io" NOT FOR THE MOMENT

module("splay.restricted_db")

_COPYRIGHT   = "Copyright 2010 José Valerio (University of Neuchâtel)"
_DESCRIPTION = "Restricted DB"
_VERSION     = 1.0

--[[ DEBUG ]]--
l_o = log.new(1, "[".._NAME.."]")

--TODO

-- Dangerous functions

--[[ Config ]]--

local dir = "." --pseudo root dir
local prefix = "pdb_"

--[[ Init ]]--

local init_done = false
function init(directory)
	if not init_done then
		init_done = true
		if not directory then l_o:debug("no directory") end

		l_o:debug("directory="..directory)

		local l_dir = directory

		l_o:debug("l_dir="..l_dir)

		if not l_dir then
			l_o:debug("l_dir=nil, no dir")
			return false, "no dir"
		end

		if l_dir == "/" then
			l_dir = dir
		end

		if string.sub(l_dir, #l_dir, #l_dir) == "/" then
			return false, "dir must not end with a /"
		end

		--[[ TODO: HOW TO CHECK L_DIR
		local f, error_msg1 = io.open(l_dir, "r")
		
		if f then -- Dir is OK
			l_o:debug("dir is OK")
			dir = l_dir
		else
			l_o:debug("dir is not OK:"..error_msg1)
		end
		--]]
		dir = l_dir
		--TODO possible initialization of variables
	else
		l_o:debug("init() already called")
	end
end

local dbs = {}

--[[ Stats ]]--

----------------------------------------------------------------
----------------------------------------------------------------

--function open(table_name, mode, flags) --mode: hash, tree JV: version with flags
function open(table_name, mode) --mode: hash, tree
 	--[[
	print("restricted_io stats")
	print(rio.stats())
	print("restricted_io limits")
	print(rio.limits())
	--]]
	local d = evp.new("md5")
	local dbf_name = prefix..d:digest(table_name)
	l_o:debug("creating DB="..dir.."/"..dbf_name)
	dbs[table_name] = kc.DB:new()
	if mode == "tree" then
		--dbs[table_name]:open(dir.."/"..dbf_name..".kct", flags)
		return dbs[table_name]:open(dir.."/"..dbf_name..".kct")
	elseif mode == "hash" then
		--dbs[table_name]:open(dir.."/"..dbf_name..".kch", flags)
		return dbs[table_name]:open(dir.."/"..dbf_name..".kch")
	else
		return false, "incorrect mode"
	end
end

function tables()
	local ret_table = {}
	for i,_ in orig_pairs(dbs) do
		ret_table[#ret_table+1]=i
	end
	return ret_table
end

function totable(table_name)
	local ret_table = {}
	for i,v in dbs[table_name]:pairs() do
		ret_table[i]=v
	end
	return ret_table
end

function exists(table_name)
	if dbs[table_name] then return true else return false end
end

function check(table_name, key)
	if not dbs[table_name] then return -1 else return dbs[table_name]:check(key) end
end

function size(table_name)
	return dbs[table_name]:size()
end

function count(table_name)
	return dbs[table_name]:count()
end

function clear(table_name)
	return dbs[table_name]:clear()
end

function replace(table_name, key, value)
	return dbs[table_name]:replace(key, value)
end

function pairs(table_name)
	return dbs[table_name]:pairs()
end

function remove(table_name, key)
	dbs[table_name]:remove(key)
end

function synchronize(table_name)
	dbs[table_name]:synchronize()
end

function get(table_name, key)
	return dbs[table_name]:get(key)
end

function set(table_name, key, value)
	return dbs[table_name]:set(key, value)
end

function close(table_name)
	dbs[table_name]:close()
end

Error = kc.Error
Cursor = kc.Cursor
VERSION = kc.VERSION
--[[
JV: version with flags
OWRITER = kc.DB.OWRITER
OCREATE = kc.DB.OCREATE
OAUTOSYNC = kc.DB.OAUTOSYNC
]]