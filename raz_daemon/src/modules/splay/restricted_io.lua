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

--[[

Restricted IO
-------------

Provides a secure version of Lua IO functions.


io.popen() -- DANGEROUS
io.tmpfile () -- DANGEROUS

io.close() => default_output_file:close()
io.close(file) => file:close()

io.flush() => default_output_file:flush()

io.input() => return default_input_file
io.input(file) => default_input_file = file, return default_input_file

io.lines() => default_input_file:lines()
io.lines(filename) => open new file, then file:lines() + CLOSE

io.open(filename[, mode]) => return new file

io.output() => return default_output_file
io.output(file) => default_output_file = file

io.read(...) => default_input_file:read(...)

io.write(...) => default_output_file:write(...)

file:close()
file:flush()
file:lines()
file:read(...)
file:seek([whence][, offset])
file:setvbuf(mode[, size])
file:write(...)

]]

local math = require"math"
local io = require"io"
local os = require"os"
local string = require"string"
local crypto = require"crypto"
local evp = crypto.evp
local log = require"splay.log"

local setmetatable = setmetatable
local unpack = unpack
local pairs = pairs
local print = print

--module("splay.restricted_io")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Restricted IO"
_M._VERSION     = 1.0

--[[ DEBUG ]]--
_M.l_o = log.new(3, "[splay.restricted_io]")

-- Dangerous functions
popen = io.popen

stdin = io.stdin
stdout = io.stdout
stderr = io.stderr

default_input_file = io.stdin
default_output_file = io.stdout

--[[ Config ]]--

local dir = "." -- pseudo root dir
local max_files = math.huge
local max_size = math.huge
local max_file_descriptors = math.huge
local prefix = "pfs_"

--[[ Init ]]--

local init_done = false
function _M.init(settings)
	if not init_done then
		init_done = true
		if not settings then return false, "no settings" end

		local l_dir = settings.directory

		if not l_dir then
			return false, "no dir"
		end

		if l_dir == "/" then
			l_dir = dir
		end

		if string.sub(l_dir, #l_dir, #l_dir) == "/" then
			return false, "dir must not end with a /"
		end

		local f = io.open(l_dir, "r")

		if f then -- Dir is OK
			dir = l_dir

			if not settings.keep_popen then
				popen = nil
			end

			if settings.no_std then
				stdin = nil
				default_input_file = nil
				stdout = nil
				default_output_file = nil
				stderr = nil
			end
			if settings.no_stdin then
				stdin = nil
				default_input_file = nil
			end
			if settings.no_stdout then
				stdout = nil
				default_output_file = nil
			end
			if settings.no_stderr then
				stderr = nil
			end

			if settings.max_file_descriptors then
				max_file_descriptors = settings.max_file_descriptors
			end
			if settings.max_size then max_size = settings.max_size end
			if settings.max_files then max_files = settings.max_files end

			if settings.clean then
				-- WARNING not portable !
				os.execute("rm "..l_dir.."/"..prefix.."* > /dev/null 2>&1")
			end
			return true
		else
			return false, "can't open dir"
		end
	else
		return false, "init() already called"
	end
end

-- Array of file names
local fs = {} -- fs[name] => size
local total_files = 0
local total_size = 0
local total_file_descriptors = 0

--[[ Stats ]]--

local function get_total_size()
	local total_size = 0
	for i, size in pairs(fs) do
		print(i, size)
		total_size = total_size + size
	end
	return total_size
end

function _M.infos()
	print("Total files: "..total_files.." (max: "..max_files..")")
	print("Total size: "..total_size.." (max: "..max_size..")")
	--print("Total size (add): "..get_total_size())
	print("Total file descriptors: "..total_file_descriptors.." (max: "..max_file_descriptors..")")
end

function _M.limits()
	return max_files, max_size, max_file_descriptors
end

function _M.stats()
	return total_files, total_size, total_file_descriptors
end

----------------------------------------------------------------
----------------------------------------------------------------

function _M.open(name, flags)

	if total_file_descriptors >= max_file_descriptors then
		l_o:warn("Open restricted (max file descriptors)")
		return nil, "Maximum file descriptors reached"
	end
	if not fs[name] and total_files >= max_files then
		l_o:warn("Open restricted (max files)")
		return nil, "Maximum number of files reached."
	end

	total_file_descriptors = total_file_descriptors + 1

	local d = evp.new("md5")
	local fs_name = prefix..d:digest(name)

	local ori_file = io.open(dir.."/"..fs_name, flags)

	if not ori_file then
		return nil, "Error opening file "..name
	end

	if not fs[name] then
		fs[name] = 0
		total_files = total_files + 1
	else
		if flags == "w" or flags == "w+" then -- We truncate the previous file
			current_pos = 0
			total_size = total_size - fs[name]
			fs[name] = 0
		end
	end

	local pfs_file = {} -- pseudo file
	local current_pos = 0 -- position in file

	if flags == "a" or flags == "a+" then
		current_pos = fs[name]
	end

	local mt = {}
	-- This file is called with ':', so the 'self' refer to ori_file but, in
	-- the call, self is the wrapping table, we need to replace it by ori_file.
	mt.__index = function(table, key)
		return function(self, ...)
			--l_o:debug("ori_file." .. key .. "()")
			return ori_file[key](ori_file, unpack(arg))
		end
	end
	setmetatable(pfs_file, mt)

	-- The effective size of the file change only when write is called.
	function pfs_file.seek(self, whence, offset)
		current_pos = ori_file.seek(ori_file, whence, offset)
		return current_pos
	end

	function pfs_file.write(self, data)
		local prev_size = fs[name]
		local data_s = #data
		if current_pos + data_s > prev_size then
			local more = current_pos + data_s - prev_size
			if total_size + more > max_size then
				l_o:warn("Write restricted (disk space)")
				return nil, "No disk space"
			else
				total_size = total_size + more
			end
		end
		current_pos = current_pos + data_s
		if current_pos > fs[name] then
			fs[name] = current_pos
		end
		return ori_file:write(data)
    end

	function pfs_file.close(self, data)
		if ori_file:close() then
			total_file_descriptors = total_file_descriptors - 1
		end
	end

	-- Shortcut for file:seek("end")
	function pfs_file.size()
		return fs[name]
  end

	return pfs_file
end

function _M.tmpfile()
	return open(math.random(2^31 - 1), "w+")
end

function _M.close(file)
	if not file then
		if default_output_file then
			return default_output_file:close()
		else
			return nil, "no default file"
		end
	else
		return file:close()
	end
end

function _M.flush()
	if default_output_file then
		return default_output_file:flush()
	else
		return nil, "no default file"
	end
end

function _M.input(file)
	if file then
		default_input_file = file
	end
	return default_input_file
end

function _M.lines(filename)
	local file = default_input_file
	if filename then
		file = _M.open(filename)
	end
	local f = file:lines()
	return function()
		if not file then
			return nil
		else
			local r = f()
			if r == nil then
				if file ~= default_input_file then
					file:close()
				end
				file = nil
			end
			return r
		end
	end
end

function _M.output(file)
	if file then
		default_output_file = file
	end
	return default_output_file
end

function _M.read(...)
	if default_input_file then
		return default_input_file:read(...)
	else
		return nil, "no default file"
	end
end

function _M.write(...)
	if default_output_file then
		return default_output_file:write(...)
	else
		return nil, "no default file"
	end
end

_M.type = io.type

-----------------------------------------------------------
------------- additionnal functions
----------------------------------------------------------

-- Link from os.remove(name)
function _M.remove(name)
	if not fs[name] then
		return nil, "File not found: "..name
	else
		local d = evp.new("md5")
		local fs_name = d:digest(name)
		local ok, msg = os.remove(dir.."/"..prefix..fs_name)
		if ok then
			total_size = total_size - fs[name]
			fs[name] = nil
			return true
		else
			return nil, "Can't remove "..name..": "..msg
		end
	end
end

-- Link from os.rename(oldname, newname)
function _M.rename(old_name, new_name)
		local d = evp.new("md5")
		local o_n = d:digest(old_name)
		d = evp.new("md5")
		local n_n = d:digest(new_name)
		return os.rename(dir.."/"..prefix..o_n, dir.."/"..prefix..n_n)
end

-- Link from os.tmpname()
function _M.tmpname()
	local d = evp.new("md5")
	return d:digest(math.random(2^31 - 1))
end

function _M.exists(name)
	if fs[name] then
		return true
	else
		return false
	end
end

-- Remove everything
function _M.clean()
	for name, _ in pairs(fs) do
		remove(name)
	end
end

function _M.list()
	return fs
end

return _M
