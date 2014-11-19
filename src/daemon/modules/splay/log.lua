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
Base log class. Everything is global, so you can override everything when
needed. Some outputs function are available in splay.out.

When you change the debug module, you will affect all the debug objects that
have kept the default behavior. It's a way to set global settings/default.
Then, inside each debug object created with new(), you can also redefine
every settings.

Overridable/settable globally:
 	global_level: all the levels
 	global_out(): all the out ready to be written
 	global_write(): to change the string appearance
 	global_filter(): to change how the debug is done

In log objects:
	prefix
	level
 	out()
 	write()
 	filter()

This class must have no dependencies on other modules when loading (to avoid
require dead lock). You can then overload functions using these modules (io,
network, ...).

We do not include out.* functions here because, for example, network logging
will require to load "splay.socket" that requires too "splay.log" (circular
dependencies).
]]

local io = require"io"

local tostring = tostring
local type = type
local ori_print = print

--module("splay.log")
local _M = {}
_M._NAME = "splay.log"
_M._COPYRIGHT   = "Copyright 2006 - 2014"
_M._DESCRIPTION = "Splay Log"
_M._VERSION     = 1.0

-- default level
_M.global_level = 3

-- default out (outs support only one parameter !)
function _M.global_out(msg)
	local msg = msg or ""
	ori_print(tostring(msg))
	io.flush()
end

-- not do any level filtering here
function _M.global_write(level, ...)
	local m = ""
	local arg= {...}
	-- do not use ipairs, first arg nil => end the loop !
	local first = true
	for i = 1, #arg do
		if first then 
			m = m..tostring(arg[i])
			first = false
		else 
			m = m.."    "..tostring(arg[i])
		end
	end

	if level == 1 then -- debug
		m = "D: "..m
	elseif level == 2 then -- notice
		m = "N: "..m
	elseif level == 3 then -- warning
		m = "W: "..m
	elseif level == 4 then -- error
		m = "E: "..m
	end
	return m
end

function _M.global_filter(self, level, ...)
	local my_level = level or _M.global_level
	local my_out = _M.out or _M.global_out
	local my_write = _M.write or _M.global_write
	
	if not (my_level and my_out and my_write) then
		print("missing function(s)")
		return false, "missing function(s)"
	end
	if level >= my_level then
		local msg = my_write(level, ...)
		if self.prefix then msg = self.prefix.." "..msg end
		my_out(msg)
		return true
	else
		return false
	end
end

function _M.new(level, prefix)
	return {
		level = level,
		prefix = prefix,
		filter = _M.global_filter,
		debug = function(self, ...) return self:filter(1, ...) end,
		notice = function(self, ...) return self:filter(2, ...) end,
		warning = function(self, ...) return self:filter(3, ...) end,
		error = function(self, ...) return self:filter(4, ...) end,
		print = function(self, ...) return self:filter(5, ...) end,
		-- aliases
		info = function(self, ...) return self:filter(2, ...) end,
		warn = function(self, ...) return self:filter(3, ...) end,
		d = function(self, ...) return self:filter(1, ...) end,
		n = function(self, ...) return self:filter(2, ...) end,
		i = function(self, ...) return self:filter(2, ...) end,
		w = function(self, ...) return self:filter(3, ...) end,
		e = function(self, ...) return self:filter(4, ...) end,
		p = function(self, ...) return self:filter(5, ...) end,
	}
end

-- to warn users that still use previous syntax
local function check(self, l, ...)
	if not self or
			type(self) ~= "table" or
			(type(self) == "table" and not self.global_filter) then
		ori_print("invalid call, use 'log:', not 'log.'")
		return false
	else
		return _M.global_filter(l, ...)
	end
end

_M.debug   = function(self, ...) return _M.check(self, 1, ...) end
_M.notice  = function(self, ...) return _M.check(self, 2, ...) end
_M.warning = function(self, ...) return _M.check(self, 3, ...) end
_M.error   = function(self, ...) return _M.check(self, 4, ...) end
_M.print   = function(self, ...) return _M.check(self, 5, ...) end

-- aliases
_M.info = _M.notice
_M.warn = _M.warning
_M.d = _M.debug
_M.n = _M.notice
_M.i = _M.info
_M.w = _M.warning
_M.e = _M.error
_M.p = _M.print

return _M