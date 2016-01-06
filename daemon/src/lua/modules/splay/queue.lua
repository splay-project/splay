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

--module("splay.queue")
local _M = {}
_M._COPYRIGHT   = "Copyright 2006 - 2011"
_M._DESCRIPTION = "Queue object"
_M._VERSION     = 1.0
_M._NAME 		=	"splay.queue"
function _M.new()

	local queue = {}
	local objects = {}

	queue.size = function()
		return #objects
	end
	queue.empty = function()
		if #objects == 0 then
			return true
		else
			return false
		end
	end
	queue.flush = function()
		objects = {}
	end
	queue.insert = function(o)
		objects[#objects + 1] = o
	end
	queue.get = function()
		if #objects == 0 then return nil end
		local o = objects[1]
		if #objects == 1 then
			objects = {}
		else
			for i = 2, #objects do
				objects[i - 1] = objects[i]
				objects[i] = nil
			end
		end
		return o
	end

	return queue
end

return _M