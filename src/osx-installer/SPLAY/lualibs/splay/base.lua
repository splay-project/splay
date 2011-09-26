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

--[[
-- Load basic splay functions. Anyway, they are already loaded by the splayd,
-- there is no memory to win, not loading them directly.
--]]

coxpcall = require"splay.coxpcall"
pcall = coxpcall.pcall
xpcall = coxpcall.xpcall

-- socket_events is a global too
socket = require"splay.socket"

events = require"splay.events"
log = require"splay.log"
misc = require"splay.misc"

if job and job.position and type(job.position) == "number" then
	math.randomseed(misc.time() + (job.position * 100000))
else
	math.randomseed(misc.time() * 10000)
end

return true
